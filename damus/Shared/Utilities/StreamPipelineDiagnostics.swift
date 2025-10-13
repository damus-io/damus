//
//  StreamPipelineDiagnostics.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-10-15.
//
import Foundation

let ENABLE_PIPELINE_DIAGNOSTICS = false

fileprivate func getTimestamp() -> String {
    let d = Date()
    let df = DateFormatter()
    df.dateFormat = "y-MM-dd H:mm:ss.SSSS"

    return df.string(from: d)
}

/// Logs stream pipeline data in CSV format that can later be used for plotting and analysis
/// See `devtools/visualize_stream_pipeline.py`
///
/// Implementation note: This function is inlined for performance purposes.
@inline(__always) func logStreamPipelineStats(_ sourceNode: String, _ destinationNode: String) {
    if ENABLE_PIPELINE_DIAGNOSTICS {
        print("STREAM_PIPELINE: \(getTimestamp()),\(sourceNode),\(destinationNode)")
    }
}
