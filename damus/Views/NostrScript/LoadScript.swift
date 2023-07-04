//
//  LoadScript.swift
//  damus
//
//  Created by William Casarin on 2023-07-04.
//

import SwiftUI

struct ScriptLoaded {
    let script: NostrScript
    let state: LoadedState
}

enum LoadedState {
    case loaded
    case running
    case ran(NostrScriptRunResult)
}

enum LoadScriptState {
    case not_loaded
    case loading
    case loaded(ScriptLoaded)
    case failed(NostrScriptLoadErr)
    
    static func loaded(script: NostrScript) -> LoadScriptState {
        return .loaded(ScriptLoaded(script: script, state: .loaded))
    }
}

class ScriptModel: ObservableObject {
    var data: [UInt8]
    @Published var state: LoadScriptState
    
    init(data: [UInt8], state: LoadScriptState) {
        self.data = data
        self.state = state
    }
    
    func run() async {
        guard case .loaded(let script) = state else {
            return
        }
        self.state = .loaded(.init(script: script.script, state: .running))
        
        let t = Task.detached {
            return script.script.run()
        }
        
        let res = await t.value
        self.state = .loaded(.init(script: script.script, state: .ran(res)))
    }
    
    @MainActor
    func load(pool: RelayPool) async {
        guard case .not_loaded = state else {
            return
        }
        self.state = .loading
        let script = NostrScript(pool: pool, data: self.data)
        let t = Task.detached {
            print("loading script")
            return script.load()
        }
        
        let load_err = await t.value
        
        let t2 = Task { @MainActor in
            if let load_err {
                self.state = .failed(load_err)
                return
            }
            
            self.state = .loaded(script: script)
        }
        
        await t2.value
    }
}

struct LoadScript: View {
    let pool: RelayPool
    
    @ObservedObject var model: ScriptModel
    
    func ScriptView(_ script: ScriptLoaded) -> some View {
        ScrollView {
            VStack {
                let imports = script.script.imports()
                
                (Text(verbatim: "\(imports.count)") +
                 Text(" Imports"))
                    .font(.title)
                
                ForEach(imports.indices, id: \.self) { ind in
                    Text(imports[ind])
                }
                
                switch script.state {
                case .loaded:
                    BigButton("Run") {
                        Task {
                            await model.run()
                        }
                    }
                case .running:
                    Text("Running...")
                case .ran(let result):
                    switch result {
                    case .runtime_err(let errs):
                        Text("Runtime error")
                            .font(.title2)
                        ForEach(errs.indices, id: \.self) { ind in
                            Text(verbatim: errs[ind])
                        }
                    case .suspend:
                        Text("Ran to suspension.")
                    case .finished(let code):
                        Text("Executed successfuly, returned with code \(code)")
                    }
                }
            }
        }
    }
    
    var body: some View {
        Group {
            switch self.model.state {
            case .not_loaded:
                ProgressView()
                    .progressViewStyle(.circular)
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
            case .loaded(let loaded):
                ScriptView(loaded)
            case .failed(let load_err):
                VStack(spacing: 20) {
                    Text("NostrScript Error")
                        .font(.title)
                    switch load_err {
                    case .parse:
                        Text("Failed to parse")
                    case .module_init:
                        Text("Failed to initialize")
                    }
                }
            }
        }
        .task {
            await model.load(pool: self.pool)
        }
        .navigationTitle("NostrScript")
    }
}


/*
 #Preview {
 LoadScript()
 }
 */
