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

setup_environment() {
    log_info "Setting up performance testing environment..."
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Check system requirements
    if [[ $(uname -m) != "arm64" ]]; then
        log_error "Performance tests require Apple Silicon (arm64)"
        exit 2
    fi
    
    if [[ $(sw_vers -productVersion | cut -d. -f1) -lt 13 ]]; then
        log_error "Performance tests require macOS 13+ (Ventura)"
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
    swift test --filter PerformanceTestSuite \
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
    
    # Create a simple Swift script to run benchmarks
    cat > "$RESULTS_DIR/run_benchmarks.swift" << 'EOF'
import Foundation

// Import WhisperNode framework
#if canImport(WhisperNode)
import WhisperNode

@main
struct BenchmarkRunner {
    static func main() async {
        let runner = PerformanceBenchmarkRunner()
        let results = await runner.runAllBenchmarks()
        
        // Output results as JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(results)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error encoding results: \(error)")
            exit(1)
        }
    }
}
EOF
    
    # Run the benchmark suite
    swift run -c release "$RESULTS_DIR/run_benchmarks.swift" > "$benchmark_results_file" 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Benchmark suite completed"
        validate_benchmark_results "$benchmark_results_file"
    else
        log_error "Benchmark suite failed"
        return 1
    fi
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
    
    overall_passed = results.get("overallPassed", False)
    test_results = results.get("results", [])
    
    print(f"\\n{'='*60}")
    print(f"PERFORMANCE VALIDATION RESULTS")
    print(f"{'='*60}")
    print(f"Overall Status: {'PASSED' if overall_passed else 'FAILED'}")
    print(f"Tests Run: {len(test_results)}")
    print(f"Timestamp: {results.get('timestamp', 'Unknown')}")
    print(f"{'='*60}")
    
    failed_tests = []
    
    for test in test_results:
        test_name = test.get("testName", "Unknown")
        value = test.get("value", 0)
        threshold = test.get("threshold", 0)
        unit = test.get("unit", "")
        passed = test.get("passed", False)
        
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {test_name}: {value} {unit} (≤ {threshold} {unit})")
        
        if not passed:
            failed_tests.append(test_name)
    
    print(f"{'='*60}")
    
    if failed_tests:
        print(f"FAILED TESTS ({len(failed_tests)}):")
        for test in failed_tests:
            print(f"  - {test}")
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