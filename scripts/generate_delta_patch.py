#!/usr/bin/env python3
"""
Al-Mudeer Delta Patch Generator

Generates binary patches (bsdiff format) between two APK versions for efficient delta updates.

Usage:
  python generate_delta_patch.py --old almudeer_v10.apk --new almudeer_v11.apk --output patches/

Requirements:
  pip install bsdiff4

Features:
  - Generates binary patch using bsdiff algorithm
  - Calculates patch size and compression ratio
  - Creates metadata JSON for the patch
  - Validates patch integrity
  - Supports batch generation for multiple architectures

Output:
  - patch_file.patch - Binary patch file
  - patch_file.meta.json - Metadata including sizes, hashes, etc.
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone

try:
    import bsdiff4
except ImportError:
    print("❌ Error: bsdiff4 not installed. Run: pip install bsdiff4")
    sys.exit(1)


def calculate_sha256(file_path: str) -> str:
    """Calculate SHA256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()


def get_file_size_mb(file_path: str) -> float:
    """Get file size in megabytes."""
    return os.path.getsize(file_path) / (1024 * 1024)


def generate_patch(old_apk: str, new_apk: str, output_dir: str, verbose: bool = False) -> dict:
    """
    Generate a binary patch between two APK files.
    
    Args:
        old_apk: Path to old APK file
        new_apk: Path to new APK file
        output_dir: Directory to save patch files
        verbose: Print verbose output
        
    Returns:
        Dictionary with patch metadata
    """
    # Validate input files
    if not os.path.exists(old_apk):
        raise FileNotFoundError(f"Old APK not found: {old_apk}")
    if not os.path.exists(new_apk):
        raise FileNotFoundError(f"New APK not found: {new_apk}")
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Get file info
    old_size = get_file_size_mb(old_apk)
    new_size = get_file_size_mb(new_apk)
    old_hash = calculate_sha256(old_apk)
    new_hash = calculate_sha256(new_apk)
    
    # Extract build numbers from filenames
    old_build = extract_build_number(old_apk)
    new_build = extract_build_number(new_apk)
    
    # Generate patch filename
    patch_filename = f"almudeer_{old_build}_to_{new_build}.patch"
    patch_path = os.path.join(output_dir, patch_filename)
    
    if verbose:
        print(f"📦 Generating delta patch...")
        print(f"   Old APK: {old_apk} ({old_size:.1f} MB)")
        print(f"   New APK: {new_apk} ({new_size:.1f} MB)")
        print(f"   Output:  {patch_path}")
    
    # Generate binary patch
    try:
        bsdiff4.file_patch(old_apk, new_apk, patch_path)
    except Exception as e:
        print(f"❌ Error generating patch: {e}")
        raise
    
    # Get patch info
    patch_size = get_file_size_mb(patch_path)
    patch_hash = calculate_sha256(patch_path)
    
    # Calculate compression ratio
    compression_ratio = (1 - patch_size / new_size) * 100 if new_size > 0 else 0
    
    # Create metadata
    metadata = {
        "patch_file": patch_filename,
        "old_apk": {
            "filename": os.path.basename(old_apk),
            "build_number": old_build,
            "size_mb": round(old_size, 2),
            "sha256": old_hash,
        },
        "new_apk": {
            "filename": os.path.basename(new_apk),
            "build_number": new_build,
            "size_mb": round(new_size, 2),
            "sha256": new_hash,
        },
        "patch": {
            "filename": patch_filename,
            "size_mb": round(patch_size, 2),
            "size_bytes": os.path.getsize(patch_path),
            "sha256": patch_hash,
            "compression_ratio": round(compression_ratio, 1),
        },
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "bsdiff_version": bsdiff4.__version__ if hasattr(bsdiff4, '__version__') else "unknown",
    }
    
    # Save metadata
    meta_path = patch_path + ".meta.json"
    with open(meta_path, "w") as f:
        json.dump(metadata, f, indent=2)
    
    if verbose:
        print(f"\n✅ Patch generated successfully!")
        print(f"   Patch size: {patch_size:.2f} MB")
        print(f"   Compression: {compression_ratio:.1f}% smaller than full APK")
        print(f"   Metadata: {meta_path}")
    
    return metadata


def extract_build_number(apk_filename: str) -> str:
    """
    Extract build number from APK filename.
    
    Examples:
        almudeer_v10.apk -> 10
        almudeer_arm64_v8a_v15.apk -> 15
        almudeer.apk -> unknown
    """
    filename = os.path.basename(apk_filename)
    
    # Try to find version pattern
    import re
    match = re.search(r'_v(\d+)', filename)
    if match:
        return match.group(1)
    
    # Try to find build number in format like almudeer_10.apk
    match = re.search(r'_(\d+)\.apk$', filename)
    if match:
        return match.group(1)
    
    return "unknown"


def batch_generate(
    old_dir: str,
    new_dir: str,
    output_dir: str,
    architectures: list = None,
    verbose: bool = False
) -> list:
    """
    Generate patches for multiple architectures.
    
    Args:
        old_dir: Directory containing old APKs
        new_dir: Directory containing new APKs
        output_dir: Directory to save patches
        architectures: List of architectures to process (default: all)
        verbose: Print verbose output
        
    Returns:
        List of patch metadata dictionaries
    """
    if architectures is None:
        architectures = ["universal", "arm64_v8a", "armeabi_v7a", "x86_64"]
    
    patches = []
    
    for arch in architectures:
        # Find APK files
        old_pattern = f"almudeer_{arch}.apk" if arch != "universal" else "almudeer.apk"
        new_pattern = f"almudeer_{arch}.apk" if arch != "universal" else "almudeer.apk"
        
        old_apk = os.path.join(old_dir, old_pattern)
        new_apk = os.path.join(new_dir, new_pattern)
        
        if not os.path.exists(old_apk):
            if verbose:
                print(f"⚠️  Skipping {arch}: old APK not found")
            continue
        
        if not os.path.exists(new_apk):
            if verbose:
                print(f"⚠️  Skipping {arch}: new APK not found")
            continue
        
        try:
            metadata = generate_patch(old_apk, new_apk, output_dir, verbose)
            metadata["architecture"] = arch
            patches.append(metadata)
        except Exception as e:
            print(f"❌ Error generating patch for {arch}: {e}")
    
    # Generate summary
    if patches:
        summary = {
            "total_patches": len(patches),
            "total_patch_size_mb": round(sum(p["patch"]["size_mb"] for p in patches), 2),
            "avg_compression_ratio": round(sum(p["patch"]["compression_ratio"] for p in patches) / len(patches), 1),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "patches": patches,
        }
        
        summary_path = os.path.join(output_dir, "patch_summary.json")
        with open(summary_path, "w") as f:
            json.dump(summary, f, indent=2)
        
        if verbose:
            print(f"\n📊 Summary:")
            print(f"   Total patches: {len(patches)}")
            print(f"   Total size: {summary['total_patch_size_mb']:.2f} MB")
            print(f"   Avg compression: {summary['avg_compression_ratio']:.1f}%")
            print(f"   Summary: {summary_path}")
    
    return patches


def verify_patch(patch_path: str, old_apk: str, expected_new_hash: str) -> bool:
    """
    Verify that a patch produces the correct output.
    
    Args:
        patch_path: Path to patch file
        old_apk: Path to old APK file
        expected_new_hash: Expected SHA256 of patched file
        
    Returns:
        True if verification passes
    """
    import tempfile
    
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp_path = tmp.name
    
    try:
        # Apply patch
        bsdiff4.file_patch(old_apk, patch_path, tmp_path)
        
        # Verify hash
        actual_hash = calculate_sha256(tmp_path)
        
        if actual_hash != expected_new_hash:
            print(f"❌ Patch verification failed!")
            print(f"   Expected: {expected_new_hash}")
            print(f"   Actual:   {actual_hash}")
            return False
        
        print(f"✅ Patch verification passed!")
        return True
        
    finally:
        # Cleanup
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def main():
    parser = argparse.ArgumentParser(
        description="Generate delta patches for Al-Mudeer APK updates",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate single patch
  python generate_delta_patch.py --old almudeer_v10.apk --new almudeer_v11.apk --output patches/
  
  # Generate patches for all architectures
  python generate_delta_patch.py --old-dir builds/v10/ --new-dir builds/v11/ --output patches/v10_to_v11/
  
  # Generate and verify patch
  python generate_delta_patch.py --old almudeer_v10.apk --new almudeer_v11.apk --output patches/ --verify
        """
    )
    
    # Single patch mode
    parser.add_argument("--old", help="Path to old APK file")
    parser.add_argument("--new", help="Path to new APK file")
    
    # Batch mode
    parser.add_argument("--old-dir", help="Directory containing old APKs (for batch mode)")
    parser.add_argument("--new-dir", help="Directory containing new APKs (for batch mode)")
    
    # Output
    parser.add_argument("--output", required=True, help="Output directory for patches")
    
    # Options
    parser.add_argument("--arch", action="append", help="Architecture to process (can be repeated)")
    parser.add_argument("--verify", action="store_true", help="Verify patch after generation")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    try:
        # Batch mode or single patch mode?
        if args.old_dir and args.new_dir:
            # Batch mode
            patches = batch_generate(
                args.old_dir,
                args.new_dir,
                args.output,
                architectures=args.arch,
                verbose=args.verbose
            )
            
            if not patches:
                print("⚠️  No patches generated")
                sys.exit(1)
                
        elif args.old and args.new:
            # Single patch mode
            metadata = generate_patch(args.old, args.new, args.output, args.verbose)
            
            # Verify if requested
            if args.verify:
                print("\n🔍 Verifying patch...")
                patch_path = os.path.join(args.output, metadata["patch"]["filename"])
                success = verify_patch(patch_path, args.old, metadata["new_apk"]["sha256"])
                sys.exit(0 if success else 1)
        else:
            parser.error("Either --old/--new or --old-dir/--new-dir must be specified")
            
    except FileNotFoundError as e:
        print(f"❌ {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
