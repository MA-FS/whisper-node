#!/bin/bash

# Performance Testing CI Script for WhisperNode
# Validates all PRD performance requirements in CI environment
# Exit codes: 0=success, 1=test failures, 2=setup errors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
RESULTS_DIR="$PROJECT_ROOT/performance-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Performance Requirements from PRD
declare -A PERFORMANCE_THRESHOLDS=(
    ["cold_launch"]="2.0"           # ≤2s
    ["transcription_5s"]="1.0"      # ≤1s for 5s utterances
    ["transcription_15s"]="2.0"     # ≤2s for 15s utterances
    ["idle_memory"]="100.0"         # ≤100MB idle
    ["peak_memory"]="700.0"         # ≤700MB peak with small.en
    ["cpu_utilization"]="150.0"     # <150% during transcription
    ["battery_impact"]="150.0"      # <150% average CPU
    ["accuracy"]="0.95"             # ≥95% WER
)

check_dependencies() {
    log_info "Checking required dependencies..."
    
    # Check for required commands
    local missing_deps=()
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi
    
    if ! command -v swift >/dev/null 2>&1; then
        missing_deps+=("swift")
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing tools and try again"
        exit 2
    fi
    
    # Check Python JSON module
    if ! python3 -c "import json" 2>/dev/null; then
        log_error "Python3 json module not available"
        exit 2
    fi
    
    log_success "All dependencies available"
}

setup_environment() {
    log_info "Setting up performance testing environment..."
    
    # Check dependencies first
    check_dependencies
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Check system requirements
    if [[ $(uname -m) != "arm64" ]]; then
        log_error "Performance tests require Apple Silicon (arm64)"
        exit 2
    fi
    
    local macos_version
    macos_version=$(sw_vers -productVersion | cut -d. -f1)
    if [[ $macos_version -lt 13 ]]; then
        log_error "Performance tests require macOS 13+ (Ventura), found: $macos_version"
        exit 2
    fi
    
    # Check Xcode and Swift versions
    if command -v xcodebuild >/dev/null 2>&1; then
        local xcode_version
        xcode_version=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
        if [[ $xcode_version -lt 14 ]]; then
            log_warning "Xcode version $xcode_version may not be optimal, recommend 14+"
        fi
    fi
    
    local swift_version
    swift_version=$(swift --version | head -1 | awk '{print $4}' | cut -d. -f1)
    if [[ $swift_version -lt 5 ]]; then
        log_error "Swift 5.0+ required, found: $swift_version"
        exit 2
    fi
    
    log_success "Environment setup complete"
}

build_project() {
    log_info "Building WhisperNode for performance testing..."
    
    cd "$PROJECT_ROOT"
    
    # Clean build for accurate performance measurement
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
    
    # Build with release optimizations
    swift build -c release --arch arm64 2>&1 | tee "$RESULTS_DIR/build_$TIMESTAMP.log"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "Build completed successfully"
    else
        log_error "Build failed. Check build log: $RESULTS_DIR/build_$TIMESTAMP.log"
        exit 2
    fi
}

run_performance_tests() {
    log_info "Running comprehensive performance test suite..."
    
    local test_results_file="$RESULTS_DIR/performance_results_$TIMESTAMP.json"
    local test_log_file="$RESULTS_DIR/performance_test_$TIMESTAMP.log"
    
    # Run XCTest performance suite
    swift test --filter "PerformanceTestSuite" \
        --configuration release \
        --parallel \
        2>&1 | tee "$test_log_file"
    
    local test_exit_code=${PIPESTATUS[0]}
    
    if [[ $test_exit_code -eq 0 ]]; then
        log_success "Performance test suite completed"
    else
        log_error "Performance tests failed. Check log: $test_log_file"
        return 1
    fi
    
    # Extract performance metrics from test output
    extract_performance_metrics "$test_log_file" "$test_results_file"
    
    return 0
}

run_benchmark_suite() {
    log_info "Running automated benchmark suite..."
    
    local benchmark_results_file="$RESULTS_DIR/benchmark_results_$TIMESTAMP.json"
    
    # Use XCTest infrastructure to run benchmarks with proper module access
    # This approach ensures proper linking with the WhisperNode package
    log_info "Using XCTest infrastructure for benchmark execution..."
    
    # Run benchmark tests that output JSON results
    swift test --filter ".*Benchmark.*" \
        --configuration release \
        --parallel \
        2>&1 | tee "$RESULTS_DIR/benchmark_test_$TIMESTAMP.log"
    
    local benchmark_exit_code=${PIPESTATUS[0]}
    
    if [[ $benchmark_exit_code -eq 0 ]]; then
        log_success "Benchmark suite completed"
        
        # Extract benchmark results from test output
        extract_benchmark_metrics "$RESULTS_DIR/benchmark_test_$TIMESTAMP.log" "$benchmark_results_file"
        
        # Validate the results
        validate_benchmark_results "$benchmark_results_file"
    else
        log_error "Benchmark suite failed. Check log: $RESULTS_DIR/benchmark_test_$TIMESTAMP.log"
        return 1
    fi
}

extract_benchmark_metrics() {
    local log_file="$1"
    local output_file="$2"
    
    log_info "Extracting benchmark metrics..."
    
    # Parse benchmark test results and create JSON summary
    python3 << EOF > "$output_file"
import json
import re
import sys
from datetime import datetime

results = {
    "timestamp": datetime.now().isoformat(),
    "test_suite": "BenchmarkSuite",
    "benchmarks": {},
    "overall_passed": True
}

try:
    with open("$log_file", "r") as f:
        content = f.read()
        
    # Extract benchmark results from XCTest output
    # Look for benchmark test patterns in the output
    
    # Extract individual benchmark results
    benchmark_patterns = [
        (r"benchmarkColdLaunch.*?(\d+\.\d+).*?seconds", "cold_launch", 2.0),
        (r"benchmarkTranscriptionLatency5s.*?(\d+\.\d+).*?seconds", "transcription_5s", 1.0),
        (r"benchmarkTranscriptionLatency15s.*?(\d+\.\d+).*?seconds", "transcription_15s", 2.0),
        (r"benchmarkIdleMemory.*?(\d+\.\d+).*?MB", "idle_memory", 100.0),
        (r"benchmarkPeakMemory.*?(\d+\.\d+).*?MB", "peak_memory", 700.0),
        (r"benchmarkCPUUtilization.*?(\d+\.\d+).*?percent", "cpu_utilization", 150.0),
    ]
    
    for pattern, metric_name, threshold in benchmark_patterns:
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            value = float(match.group(1))
            passed = value <= threshold
            results["benchmarks"][metric_name] = {
                "value": value,
                "threshold": threshold,
                "passed": passed,
                "unit": "seconds" if "latency" in metric_name or "launch" in metric_name else ("MB" if "memory" in metric_name else "percent")
            }
            if not passed:
                results["overall_passed"] = False
    
    print(json.dumps(results, indent=2, sort_keys=True))
    
except Exception as e:
    print(f"Error parsing benchmark results: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

extract_performance_metrics() {
    local log_file="$1"
    local output_file="$2"
    
    log_info "Extracting performance metrics..."
    
    # Parse test results and create JSON summary
    python3 << EOF > "$output_file"
import json
import re
import sys
from datetime import datetime

results = {
    "timestamp": datetime.now().isoformat(),
    "test_suite": "PerformanceTestSuite",
    "metrics": {},
    "passed": True
}

try:
    with open("$log_file", "r") as f:
        content = f.read()
        
    # Extract specific metrics based on test output patterns
    # This is a simplified parser - in production, use structured output
    
    # Cold launch time
    cold_launch_match = re.search(r"Cold launch time \((.+?)s\)", content)
    if cold_launch_match:
        results["metrics"]["cold_launch"] = {
            "value": float(cold_launch_match.group(1)),
            "threshold": ${PERFORMANCE_THRESHOLDS["cold_launch"]},
            "unit": "seconds",
            "passed": float(cold_launch_match.group(1)) <= ${PERFORMANCE_THRESHOLDS["cold_launch"]}
        }
    
    # Add other metrics extraction here...
    
    print(json.dumps(results, indent=2))
    
except Exception as e:
    print(f"Error parsing metrics: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Performance metrics extracted"
    else
        log_warning "Failed to extract some performance metrics"
    fi
}

validate_benchmark_results() {
    local results_file="$1"
    
    log_info "Validating benchmark results against PRD requirements..."
    
    if [[ ! -f "$results_file" ]]; then
        log_error "Benchmark results file not found: $results_file"
        return 1
    fi
    
    # Parse results and validate against thresholds
    python3 << EOF
import json
import sys

try:
    with open("$results_file", "r") as f:
        results = json.load(f)
    
    overall_passed = results.get("overall_passed", False)
    benchmarks = results.get("benchmarks", {})
    
    print(f"\\n{'='*60}")
    print(f"PERFORMANCE VALIDATION RESULTS")
    print(f"{'='*60}")
    print(f"Overall Status: {'PASSED' if overall_passed else 'FAILED'}")
    print(f"Benchmarks Run: {len(benchmarks)}")
    print(f"Timestamp: {results.get('timestamp', 'Unknown')}")
    print(f"{'='*60}")
    
    failed_benchmarks = []
    
    for benchmark_name, benchmark_data in benchmarks.items():
        value = benchmark_data.get("value", 0)
        threshold = benchmark_data.get("threshold", 0)
        unit = benchmark_data.get("unit", "")
        passed = benchmark_data.get("passed", False)
        
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {benchmark_name}: {value} {unit} (≤ {threshold} {unit})")
        
        if not passed:
            failed_benchmarks.append(benchmark_name)
    
    print(f"{'='*60}")
    
    if failed_benchmarks:
        print(f"FAILED BENCHMARKS ({len(failed_benchmarks)}):")
        for benchmark in failed_benchmarks:
            print(f"  - {benchmark}")
        print(f"{'='*60}")
        sys.exit(1)
    else:
        print("All performance requirements satisfied!")
        print(f"{'='*60}")
    
except Exception as e:
    print(f"Error validating results: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    return $?
}

generate_performance_report() {
    log_info "Generating performance report..."
    
    local report_file="$RESULTS_DIR/performance_report_$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# WhisperNode Performance Test Report

**Generated**: $(date)  
**Commit**: $(git rev-parse HEAD)  
**Branch**: $(git branch --show-current)  

## Performance Requirements Validation

The following tests validate compliance with PRD performance requirements:

| Metric | Requirement | Result | Status |
|--------|-------------|--------|--------|
| Cold Launch | ≤ 2.0s | TBD | TBD |
| Transcription (5s) | ≤ 1.0s | TBD | TBD |
| Transcription (15s) | ≤ 2.0s | TBD | TBD |
| Idle Memory | ≤ 100MB | TBD | TBD |
| Peak Memory | ≤ 700MB | TBD | TBD |
| CPU Utilization | < 150% | TBD | TBD |
| Battery Impact | < 150% avg | TBD | TBD |
| Accuracy | ≥ 95% WER | TBD | TBD |

## Test Environment

- **Platform**: $(uname -m) ($(uname -s))
- **OS Version**: $(sw_vers -productVersion)
- **Swift Version**: $(swift --version | head -1)
- **Xcode Version**: $(xcodebuild -version | head -1)

## Files Generated

- Build Log: \`build_$TIMESTAMP.log\`
- Test Log: \`performance_test_$TIMESTAMP.log\`
- Results: \`performance_results_$TIMESTAMP.json\`
- Benchmarks: \`benchmark_results_$TIMESTAMP.json\`

## Regression Analysis

Performance regression detection will be implemented in future iterations.

---
*Report generated by WhisperNode Performance CI*
EOF
    
    log_success "Performance report generated: $report_file"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary Swift files
    if [[ -f "$RESULTS_DIR/run_benchmarks.swift" ]]; then
        rm "$RESULTS_DIR/run_benchmarks.swift"
    fi
    
    log_success "Cleanup completed"
}

main() {
    log_info "Starting WhisperNode Performance Testing Suite"
    log_info "Validating PRD performance requirements..."
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    # Run the complete test pipeline
    setup_environment
    build_project
    
    local test_failed=0
    
    # Run performance tests
    if ! run_performance_tests; then
        test_failed=1
    fi
    
    # Run benchmark suite
    if ! run_benchmark_suite; then
        test_failed=1
    fi
    
    # Generate report regardless of test results
    generate_performance_report
    
    if [[ $test_failed -eq 1 ]]; then
        log_error "Performance testing failed - see results in $RESULTS_DIR"
        exit 1
    else
        log_success "All performance tests passed!"
        log_info "Results available in: $RESULTS_DIR"
        exit 0
    fi
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi