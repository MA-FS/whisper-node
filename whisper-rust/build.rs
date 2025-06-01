use std::env;

fn main() {
    let target = env::var("TARGET").expect("TARGET environment variable not set");
    
    if target.contains("aarch64-apple-darwin") {
        // Apple Silicon optimizations
        println!("cargo:rustc-link-arg=-framework");
        println!("cargo:rustc-link-arg=Foundation");
        println!("cargo:rustc-link-arg=-framework");
        println!("cargo:rustc-link-arg=Metal");
        println!("cargo:rustc-link-arg=-framework");
        println!("cargo:rustc-link-arg=MetalKit");
        println!("cargo:rustc-link-arg=-framework");
        println!("cargo:rustc-link-arg=Accelerate");
        
        // Enable Apple Silicon specific optimizations
        println!("cargo:rustc-env=CFLAGS=-march=armv8.2-a -mfpu=neon -O3");
        println!("cargo:rustc-env=CXXFLAGS=-march=armv8.2-a -mfpu=neon -O3");
    }
    
    // Tell cargo to invalidate the built crate whenever the wrapper changes
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=build.rs");
}