#!/usr/bin/env python3
"""Generate interactive Sankey diagram from network CSV data using Plotly."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple, Optional

import plotly.graph_objects as go
import plotly.express as px


def parse_timestamp(timestamp_str: str) -> float:
    """Parse timestamp string and return as milliseconds since epoch."""
    # Strip whitespace
    timestamp_str = timestamp_str.strip()
    
    # Remove any prefix (e.g., "STREAM_PIPELINE: ")
    if ": " in timestamp_str:
        timestamp_str = timestamp_str.split(": ", 1)[1]
    
    try:
        # Try parsing as ISO format with milliseconds
        dt = datetime.fromisoformat(timestamp_str)
        return dt.timestamp() * 1000
    except ValueError:
        try:
            # Try replacing space with 'T' for ISO format (e.g., "2025-10-13 15:36:46.3650")
            if " " in timestamp_str and "-" in timestamp_str:
                timestamp_str = timestamp_str.replace(" ", "T")
                dt = datetime.fromisoformat(timestamp_str)
                return dt.timestamp() * 1000
            raise ValueError()
        except ValueError:
            try:
                # Try parsing as float (milliseconds)
                return float(timestamp_str)
            except ValueError:
                raise ValueError(f"Could not parse timestamp: {timestamp_str}")


def load_network_data(csv_file: str, start_time: Optional[str] = None, 
                      end_time: Optional[str] = None) -> Dict[Tuple[str, str], int]:
    """
    Load network data from CSV and aggregate edge counts.
    
    Args:
        csv_file: Path to CSV file
        start_time: Optional start time filter (ISO format)
        end_time: Optional end time filter (ISO format)
    
    Returns:
        Dictionary mapping (source, destination) tuples to counts
    """
    edge_counts = defaultdict(int)
    timestamps = []
    
    # Parse time filters if provided
    start_ts = parse_timestamp(start_time) if start_time else None
    end_ts = parse_timestamp(end_time) if end_time else None
    
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        
        # Skip header if present
        first_row = next(reader, None)
        if first_row is None:
            print("Empty CSV file")
            return edge_counts
        
        # Check if first row is a header
        try:
            parse_timestamp(first_row[0])
            rows = [first_row]  # First row is data
        except (ValueError, IndexError):
            rows = []  # First row is header, skip it
        
        # Add remaining rows
        rows.extend(reader)
        
        for row_idx, row in enumerate(rows):
            if len(row) < 3:
                print(f"Skipping invalid row {row_idx + 1}: {row}")
                continue
            
            try:
                timestamp_str = row[0]
                source = row[1].strip()
                destination = row[2].strip()
                
                # Parse timestamp
                timestamp_ms = parse_timestamp(timestamp_str)
                
                # Apply time filters
                if start_ts and timestamp_ms < start_ts:
                    continue
                if end_ts and timestamp_ms > end_ts:
                    continue
                
                timestamps.append(timestamp_ms)
                edge_counts[(source, destination)] += 1
                
            except (ValueError, IndexError) as e:
                print(f"Error processing row {row_idx + 1}: {e}")
                continue
    
    if timestamps:
        start_dt = datetime.fromtimestamp(min(timestamps) / 1000.0)
        end_dt = datetime.fromtimestamp(max(timestamps) / 1000.0)
        print(f"\nLoaded {sum(edge_counts.values())} events")
        print(f"Time range: {start_dt} to {end_dt}")
        print(f"Unique edges: {len(edge_counts)}")
    
    return edge_counts


def filter_top_edges(edge_counts: Dict[Tuple[str, str], int], 
                     top_n: Optional[int] = None) -> Dict[Tuple[str, str], int]:
    """Filter to keep only top N most active edges."""
    if top_n is None or top_n <= 0:
        return edge_counts
    
    # Sort by count and take top N
    sorted_edges = sorted(edge_counts.items(), key=lambda x: x[1], reverse=True)
    return dict(sorted_edges[:top_n])


def filter_top_nodes(edge_counts: Dict[Tuple[str, str], int], 
                     top_n: Optional[int] = None) -> Dict[Tuple[str, str], int]:
    """Filter to keep only edges involving top N most active nodes."""
    if top_n is None or top_n <= 0:
        return edge_counts
    
    # Calculate node activity (both as source and destination)
    node_activity = defaultdict(int)
    for (source, dest), count in edge_counts.items():
        node_activity[source] += count
        node_activity[dest] += count
    
    # Get top N nodes
    top_nodes = set(sorted(node_activity.items(), key=lambda x: x[1], reverse=True)[:top_n])
    top_nodes = {node for node, _ in top_nodes}
    
    # Filter edges to only include top nodes
    filtered = {}
    for (source, dest), count in edge_counts.items():
        if source in top_nodes and dest in top_nodes:
            filtered[(source, dest)] = count
    
    return filtered


def create_sankey_diagram(edge_counts: Dict[Tuple[str, str], int],
                         title: str = "Network Flow Sankey Diagram",
                         color_scheme: str = "Viridis",
                         show_values: bool = True) -> go.Figure:
    """
    Create an interactive Sankey diagram from edge counts.
    
    Args:
        edge_counts: Dictionary mapping (source, destination) to flow count
        title: Title for the diagram
        color_scheme: Plotly color scheme name
        show_values: Whether to show flow values on hover
    
    Returns:
        Plotly Figure object
    """
    if not edge_counts:
        print("No data to visualize")
        return go.Figure()
    
    # Create node list (unique sources and destinations)
    all_nodes = set()
    for source, dest in edge_counts.keys():
        all_nodes.add(source)
        all_nodes.add(dest)
    
    # Create node index mapping
    node_list = sorted(all_nodes)
    node_to_idx = {node: idx for idx, node in enumerate(node_list)}
    
    # Prepare Sankey data
    sources = []
    targets = []
    values = []
    link_colors = []
    
    for (source, dest), count in edge_counts.items():
        sources.append(node_to_idx[source])
        targets.append(node_to_idx[dest])
        values.append(count)
    
    # Calculate node colors based on total flow
    node_flow = defaultdict(int)
    for (source, dest), count in edge_counts.items():
        node_flow[source] += count
        node_flow[dest] += count
    
    # Get color scale
    max_flow = max(node_flow.values()) if node_flow else 1
    colors = px.colors.sample_colorscale(
        color_scheme, 
        [node_flow.get(node, 0) / max_flow for node in node_list]
    )
    
    # Create link colors (semi-transparent version of source node color)
    for source_idx in sources:
        color = colors[source_idx]
        # Convert to rgba with transparency
        if color.startswith('rgb'):
            link_colors.append(color.replace('rgb', 'rgba').replace(')', ', 0.4)'))
        else:
            link_colors.append(color)
    
    # Create hover text for nodes
    node_hover = []
    for node in node_list:
        total_flow = node_flow.get(node, 0)
        # Calculate in/out flows
        inflow = sum(count for (s, d), count in edge_counts.items() if d == node)
        outflow = sum(count for (s, d), count in edge_counts.items() if s == node)
        hover_text = f"<b>{node}</b><br>"
        hover_text += f"Total Flow: {total_flow}<br>"
        hover_text += f"Inflow: {inflow}<br>"
        hover_text += f"Outflow: {outflow}"
        node_hover.append(hover_text)
    
    # Create hover text for links
    link_hover = []
    for i, ((source, dest), count) in enumerate(edge_counts.items()):
        hover_text = f"<b>{source} → {dest}</b><br>"
        hover_text += f"Flow: {count} events<br>"
        if sum(values) > 0:
            percentage = (count / sum(values)) * 100
            hover_text += f"Percentage: {percentage:.1f}%"
        link_hover.append(hover_text)
    
    # Create the Sankey diagram
    fig = go.Figure(data=[go.Sankey(
        node=dict(
            pad=15,
            thickness=20,
            line=dict(color="black", width=0.5),
            label=node_list,
            color=colors,
            customdata=node_hover,
            hovertemplate='%{customdata}<extra></extra>'
        ),
        link=dict(
            source=sources,
            target=targets,
            value=values,
            color=link_colors,
            customdata=link_hover,
            hovertemplate='%{customdata}<extra></extra>'
        )
    )])
    
    # Update layout
    fig.update_layout(
        title=dict(
            text=title,
            font=dict(size=20, color='#333')
        ),
        font=dict(size=12),
        plot_bgcolor='white',
        paper_bgcolor='white',
        height=800,
        margin=dict(l=20, r=20, t=80, b=20)
    )
    
    return fig


def print_summary_statistics(edge_counts: Dict[Tuple[str, str], int]) -> None:
    """Print summary statistics about the network flows."""
    if not edge_counts:
        print("No data to summarize")
        return
    
    print("\n" + "="*70)
    print("SANKEY DIAGRAM SUMMARY")
    print("="*70)
    
    # Calculate statistics
    total_events = sum(edge_counts.values())
    unique_edges = len(edge_counts)
    
    all_sources = {source for source, _ in edge_counts.keys()}
    all_destinations = {dest for _, dest in edge_counts.keys()}
    all_nodes = all_sources | all_destinations
    
    print(f"\nTotal Events: {total_events}")
    print(f"Unique Edges: {unique_edges}")
    print(f"Unique Nodes: {len(all_nodes)}")
    print(f"  - Source nodes: {len(all_sources)}")
    print(f"  - Destination nodes: {len(all_destinations)}")
    
    # Node activity
    node_activity = defaultdict(lambda: {'in': 0, 'out': 0, 'total': 0})
    for (source, dest), count in edge_counts.items():
        node_activity[source]['out'] += count
        node_activity[source]['total'] += count
        node_activity[dest]['in'] += count
        node_activity[dest]['total'] += count
    
    print(f"\nTop 10 Most Active Edges:")
    sorted_edges = sorted(edge_counts.items(), key=lambda x: x[1], reverse=True)
    for i, ((source, dest), count) in enumerate(sorted_edges[:10], 1):
        pct = (count / total_events) * 100
        print(f"  {i:2d}. {source:<25s} → {dest:<25s} {count:>6d} ({pct:>5.1f}%)")
    
    print(f"\nTop 10 Most Active Nodes (by total flow):")
    sorted_nodes = sorted(node_activity.items(), key=lambda x: x[1]['total'], reverse=True)
    for i, (node, flows) in enumerate(sorted_nodes[:10], 1):
        print(f"  {i:2d}. {node:<30s} Total: {flows['total']:>6d}  "
              f"(In: {flows['in']:>5d}, Out: {flows['out']:>5d})")
    
    print("\n" + "="*70 + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate interactive Sankey diagram from network CSV data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate basic Sankey diagram
  %(prog)s data.csv
  
  # Filter to top 20 edges and save to HTML
  %(prog)s data.csv --top-edges 20 --output sankey.html
  
  # Filter to top 15 nodes with custom title
  %(prog)s data.csv --top-nodes 15 --title "My Network Flows"
  
  # Filter by time range
  %(prog)s data.csv --start-time "2025-01-13 10:00:00" --end-time "2025-01-13 12:00:00"
  
  # Combine filters
  %(prog)s data.csv --top-nodes 10 --color-scheme Plasma --output flows.html
        """
    )
    
    parser.add_argument(
        "csv_file",
        type=str,
        help="Path to CSV file with format: timestamp, source_node, destination_node"
    )
    
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output HTML file path (if not specified, opens in browser)"
    )
    
    parser.add_argument(
        "--top-edges",
        type=int,
        default=None,
        help="Show only top N most active edges (default: all)"
    )
    
    parser.add_argument(
        "--top-nodes",
        type=int,
        default=None,
        help="Show only edges involving top N most active nodes (default: all)"
    )
    
    parser.add_argument(
        "--start-time",
        type=str,
        default=None,
        help="Start time filter (ISO format, e.g., '2025-01-13 10:00:00')"
    )
    
    parser.add_argument(
        "--end-time",
        type=str,
        default=None,
        help="End time filter (ISO format, e.g., '2025-01-13 12:00:00')"
    )
    
    parser.add_argument(
        "--title",
        type=str,
        default="Network Flow Sankey Diagram",
        help="Title for the diagram (default: 'Network Flow Sankey Diagram')"
    )
    
    parser.add_argument(
        "--color-scheme",
        type=str,
        default="Viridis",
        choices=["Viridis", "Plasma", "Inferno", "Magma", "Cividis", "Turbo", 
                 "Blues", "Greens", "Reds", "Purples", "Rainbow"],
        help="Color scheme for nodes (default: Viridis)"
    )
    
    parser.add_argument(
        "--no-summary",
        action="store_true",
        help="Skip printing summary statistics"
    )
    
    parser.add_argument(
        "--auto-open",
        action="store_true",
        help="Automatically open in browser (default: True if no output file specified)"
    )
    
    args = parser.parse_args()
    
    # Check if CSV file exists
    csv_path = Path(args.csv_file)
    if not csv_path.exists():
        print(f"Error: CSV file not found: {args.csv_file}")
        return
    
    # Load data
    print(f"Loading data from {args.csv_file}...")
    edge_counts = load_network_data(args.csv_file, args.start_time, args.end_time)
    
    if not edge_counts:
        print("No data to visualize!")
        return
    
    # Apply filters
    if args.top_edges:
        print(f"Filtering to top {args.top_edges} edges...")
        edge_counts = filter_top_edges(edge_counts, args.top_edges)
    
    if args.top_nodes:
        print(f"Filtering to edges involving top {args.top_nodes} nodes...")
        edge_counts = filter_top_nodes(edge_counts, args.top_nodes)
    
    # Print summary statistics
    if not args.no_summary:
        print_summary_statistics(edge_counts)
    
    # Create Sankey diagram
    print("Generating Sankey diagram...")
    fig = create_sankey_diagram(
        edge_counts,
        title=args.title,
        color_scheme=args.color_scheme
    )
    
    # Save or show
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        fig.write_html(str(output_path))
        print(f"\nSaved Sankey diagram to: {output_path}")
        print(f"Open the file in a web browser to view the interactive diagram.")
        
        if args.auto_open:
            import webbrowser
            webbrowser.open(f"file://{output_path.absolute()}")
    else:
        print("\nOpening Sankey diagram in browser...")
        fig.show()
    
    print("\nDone!")


if __name__ == "__main__":
    main()