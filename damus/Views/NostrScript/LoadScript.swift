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
    
    @MainActor
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

                let nounString = pluralizedString(key: "imports_count", count: imports.count)
                let nounText = Text(nounString).font(.title)
                Text("\(Text(verbatim: imports.count.formatted())) \(nounText)", comment: "Sentence composed of 2 variables to describe how many imports were performed from loading a NostrScript. In source English, the first variable is the number of imports, and the second variable is 'Import' or 'Imports'.")
                
                ForEach(imports.indices, id: \.self) { ind in
                    Text(imports[ind])
                }
                
                switch script.state {
                case .loaded:
                    BigButton(NSLocalizedString("Run", comment: "Button that runs a NostrScript.")) {
                        Task {
                            await model.run()
                        }
                    }
                case .running:
                    Text("Running...", comment: "Indication that the execution of a NostrScript is running.")
                case .ran(let result):
                    switch result {
                    case .runtime_err(let errs):
                        Text("Runtime error", comment: "Indication that a runtime error occurred when running a NostrScript.")
                            .font(.title2)
                        ForEach(errs.indices, id: \.self) { ind in
                            Text(verbatim: errs[ind])
                        }
                    case .suspend:
                        Text("Ran to suspension.", comment: "Indication that a NostrScript was run until it reached a suspended state.")
                    case .finished(let code):
                        Text("Executed successfully, returned with code \(code.description)", comment: "Indication that the execution of running a NostrScript finished successfully, while providing a numeric return code.")
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
                    Text("NostrScript Error", comment: "Text indicating that there was an error with loading NostrScript. There is a more descriptive error message shown separately underneath.")
                        .font(.title)
                    switch load_err {
                    case .parse:
                        Text("Failed to parse", comment: "NostrScript error message when it fails to parse a script.")
                    case .module_init:
                        Text("Failed to initialize", comment: "NostrScript error message when it fails to initialize a module.")
                    }
                }
            }
        }
        .task {
            await model.load(pool: self.pool)
        }
        .navigationTitle(NSLocalizedString("NostrScript", comment: "Navigation title for the view showing NostrScript."))
    }
}


/*
 #Preview {
 LoadScript()
 }
 */
