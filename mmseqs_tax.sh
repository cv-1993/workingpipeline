#!/bin/bash

# Pipeline for taxonomic assignment of metagenomic contigs using MMseqs2
# Input: Contigs from de novo assembly
# Requirements: MMseqs2, MMseqs database and seqTaxDB

# Exit on error
set -e

# Usage function
usage() {
    echo "Usage: $0 -c <contigs.fasta> -d <mmseqs_db_path> -o <output_dir>"
    echo "Options:"
    echo "  -c    Path to contigs FASTA file from de novo (required)"
    echo "  -d    Path to MMseqs2 database (required)"
    echo "  -o    Output directory (required)"
    echo "  -t    Number of threads (default: 28)"
    echo "  -m    Maximum memory in GB (default: 112)"
    echo "  -s    Sensitivity (default: 3)"
    echo "  -h    Show this help message"
    exit 1
}

# Default values
THREADS=28
MEMORY=112
SENSITIVITY=3

# Parse command line arguments
while getopts "c:d:o:t:m:s:h" opt; do
    case $opt in
        c) CONTIGS="$OPTARG";;
        d) MMSEQS_DB="$OPTARG";;
        o) OUTDIR="$OPTARG";;
        t) THREADS="$OPTARG";;
        m) MEMORY="$OPTARG";;
        s) SENSITIVITY="$OPTARG";;
        h) usage;;
        ?) usage;;
    esac
done

# Check for required arguments
if [ -z "$CONTIGS" ] || [ -z "$MMSEQS_DB" ] || [ -z "$OUTDIR" ]; then
    echo "Error: Required arguments missing"
    usage
fi

# Function to check if MMseqs2 is installed
check_mmseqs() {
    command -v mmseqs >/dev/null 2>&1 || { echo "MMseqs2 is required but not installed. Aborting." >&2; exit 1; }
    echo "MMseqs2 installation found."
}

# Function to create output directory structure
create_dirs() {
    echo "Creating output directory structure..."
    if mkdir -p "$OUTDIR"/logs "$OUTDIR"/tmp; then
        echo "Directories created successfully."
    else
        echo "Failed to create output directories. Aborting." >&2
        exit 1
    fi
}

# Function to create MMseqs2 database from contigs
create_mmseqs_db() {
    echo "Creating MMseqs2 database from contigs..."
    mmseqs createdb "$CONTIGS" "$OUTDIR/contig" \
        > "$OUTDIR/logs/createdb.log" 2>&1 || { echo "Failed to create MMseqs2 database" >&2; exit 1; }
}

# Function to run taxonomy assignment
run_taxonomy() {
    echo "Running taxonomy assignment..."
    mmseqs taxonomy \
        "$OUTDIR/contig" \
        "$MMSEQS_DB" \
        "$OUTDIR/lca_result" \
        "$OUTDIR/tmp" \
        -s "$SENSITIVITY" \
        --threads "$THREADS"
        > "$OUTDIR/logs/taxonomy.log" 2>&1 || { echo "Taxonomy assignment failed" >&2; exit 1; }
}

# Function to create TSV output
create_tsv() {
    echo "Creating TSV output..."
    mmseqs createtsv \
        "$OUTDIR/contig" \
        "$OUTDIR/lca_result" \
        "$OUTDIR/lca.tsv" \
        > "$OUTDIR/logs/createtsv.log" 2>&1 || { echo "TSV creation failed" >&2; exit 1; }
}

# Function to analyze contig hits
analyze_hits() {
    echo "Analyzing contig hits..."
    cut -d $'\t' -f4 "$OUTDIR/lca.tsv" | \
        sort | \
        uniq -c | \
        sort -rn > "$OUTDIR/contigs_lca.tsv" || { echo "Hit analysis failed" >&2; exit 1; }
}

# Function to create taxonomy reports
create_reports() {
    echo "Creating taxonomy reports..."
    # Create report for Pavian
    mmseqs taxonomyreport \
        "$MMSEQS_DB" \
        "$OUTDIR/lca_result" \
        "$OUTDIR/report.txt" \
        > "$OUTDIR/logs/report.log" 2>&1 || { echo "Report creation failed" >&2; exit 1; }

    # Create Krona report
    mmseqs taxonomyreport \
        "$MMSEQS_DB" \
        "$OUTDIR/lca_result" \
        "$OUTDIR/report_krona.html" \
        --report-mode 1 \
        > "$OUTDIR/logs/krona_report.log" 2>&1 || { echo "Krona report creation failed" >&2; exit 1; }
}

# Function to clean up temporary files
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$OUTDIR/tmp"
}

# Main pipeline execution
main() {
    echo "Starting taxonomic assignment pipeline using MMseqs2..."
    
    # Record start time
    start_time=$(date +%s)
    
    # Run pipeline steps
    check_mmseqs
    create_dirs
    create_mmseqs_db
    run_taxonomy
    create_tsv
    analyze_hits
    create_reports
    cleanup
    
    # Calculate runtime
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "Pipeline completed successfully in $runtime seconds!"
    echo "Output files are in: $OUTDIR"
    echo "Main output files:"
    echo "  - Taxonomy assignments: $OUTDIR/lca.tsv"
    echo "  - Contig hit summary: $OUTDIR/contigs_lca.tsv"
    echo "  - Pavian report: $OUTDIR/report.txt"
    echo "  - Krona report: $OUTDIR/report_krona.html"
    echo "Logs are in: $OUTDIR/logs"
}

# Trap cleanup on exit
trap cleanup EXIT

# Execute pipeline
main
