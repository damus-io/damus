//
//  NostrScript.swift
//  damus
//
//  Created by William Casarin on 2023-06-02.
//

import Foundation

enum NostrScriptLoadErr {
    case parse
    case module_init
}

enum NostrScriptRunResult {
    case runtime_err([String])
    case suspend
    case finished(Int)
    
    var exited: Bool {
        switch self {
        case .runtime_err:
            return true
        case .suspend:
            return false
        case .finished:
            return true
        }
    }
    
    var is_suspended: Bool {
        if case .suspend = self {
            return true
        }
        return false
    }
}

enum NostrScriptLoadResult {
    case err(NostrScriptLoadErr)
    case loaded(wasm_interp)
}

enum NostrScriptError: Error {
    case not_loaded
}

class NostrScript {
    private var interp: wasm_interp
    private var parser: wasm_parser
    var waiting_on: NScriptWaiting?
    var loaded: Bool
    var data: [UInt8]
    
    private(set) var runstate: NostrScriptRunResult?
    private(set) var pool: RelayPool
    private(set) var event: NostrResponse?
    
    init(pool: RelayPool, data: [UInt8]) {
        self.interp = wasm_interp()
        self.parser = wasm_parser()
        self.pool = pool
        self.event = nil
        self.runstate = nil
        self.loaded = false
        self.data = data
    }
    
    deinit {
        wasm_parser_free(&self.parser)
        wasm_interp_free(&self.interp)
    }
    
    func is_suspended(on: NScriptWaiting) -> Bool {
        return self.waiting_on == on
    }
    
    func can_resume(with: NScriptResumeWith) -> Bool {
        guard let waiting_on else {
            return false
        }
        switch waiting_on {
        case .event(let subid):
            switch with {
            case .event(let resp):
                return resp.subid == subid
            }
        }
    }
    
    func imports() -> [String] {
        guard self.loaded,
              was_section_parsed(interp.module, section_import) > 0,
              let module = maybe_pointee(interp.module)
        else {
            return []
        }
        
        var imports = [String]()
        
        var i = 0
        while i < module.import_section.num_imports {
            let imp = module.import_section.imports[i]
            
            imports.append(String(cString: imp.name))
            
            i += 1
        }
        
        return imports
    }
    
    func load() -> NostrScriptLoadErr? {
        guard !loaded else {
            return nil
        }
        switch nscript_load(&parser, &interp, &self.data, UInt(data.count))  {
        case NSCRIPT_LOADED:
            print("load num_exports \(interp.module.pointee.export_section.num_exports)")
            interp.context = Unmanaged.passUnretained(self).toOpaque()
            self.loaded = true
            return nil
        case NSCRIPT_INIT_ERR:
            return .module_init
        case NSCRIPT_PARSE_ERR:
            return .parse
        default:
            return .parse
        }
    }
    
    func resume(with: NScriptResumeWith) -> NostrScriptRunResult? {
        guard let runstate, runstate.is_suspended, can_resume(with: with) else {
            return nil
        }
        
        switch with {
        case .event(let resp):
            load_data(resp: resp)
        }
                
        let st = nscript_run(interp: &interp, resuming: true)
        self.runstate = st
        self.event = nil
        return st
    }
    
    private func load_data(resp: NostrResponse) {
        self.event = resp
    }
    
    func run() -> NostrScriptRunResult {
        if let runstate {
            return runstate
        }

        let st = nscript_run(interp: &interp, resuming: false)
        self.runstate = st
        return st
    }
}

fileprivate func interp_nostrscript(interp: UnsafeMutablePointer<wasm_interp>?) -> NostrScript? {
    guard let interp = interp?.pointee else {
        return nil
    }
    
    return Unmanaged<NostrScript>.fromOpaque(interp.context).takeUnretainedValue()
}

fileprivate func asm_str_byteptr(cstr: UnsafePointer<UInt8>, len: Int32) -> String? {
    let u16 = cstr.withMemoryRebound(to: UInt16.self, capacity: Int(len)) { p in p }
    return asm_str(cstr: u16, len: len)
}

fileprivate func asm_str(cstr: UnsafePointer<UInt16>, len: Int32) -> String? {
    return String(utf16CodeUnits: cstr, count: Int(len))
}

enum NScriptCommand: Int {
    case pool_send = 1
    case add_relay = 2
    case event_await = 3
    case event_get_type = 4
    case event_get_note = 5
    case note_get_kind = 6
    case note_get_content = 7
    case note_get_content_length = 8
}

enum NScriptEventType: Int {
    case ok = 1
    case note = 2
    case notice = 3
    case eose = 4
    case auth = 5

    init(resp: NostrResponse) {
        switch resp {
        case .event:
            self = .note
        case .notice:
            self = .notice
        case .eose:
            self = .eose
        case .ok:
            self = .ok
        case .auth:
            self = .auth
        }
    }
}

enum NScriptWaiting: Equatable {
    case event(String)
    
    var subid: String {
        switch self {
        case .event(let subid):
            return subid
        }
    }
}

enum NScriptResumeWith {
    case event(NostrResponse)
}

enum NScriptCmdResult {
    case suspend(NScriptWaiting)
    case ok
    case fatal
}

@_cdecl("nscript_nostr_cmd")
public func nscript_nostr_cmd(interp: UnsafeMutablePointer<wasm_interp>?, cmd: Int32, value: UnsafePointer<UInt8>, len: Int32) -> Int32 {
    guard let script = interp_nostrscript(interp: interp),
          let cmd = NScriptCommand(rawValue: Int(cmd)) else {
        return 0
    }
    
    print("nostr_cmd \(cmd)")
    
    switch cmd {
    case .pool_send:
        guard let req = asm_str_byteptr(cstr: value, len: len) else { return 0 }
        let res = nscript_pool_send(script: script, req: req)
        stack_push_i32(interp, 0);
        return res;
        
    case .add_relay:
        guard let relay = asm_str_byteptr(cstr: value, len: len) else { return 0 }
        let ok = nscript_add_relay(script: script, relay: relay)
        stack_push_i32(interp, ok ? 1 : 0)
        return 1;
        
    case .event_await:
        guard let subid = asm_str_byteptr(cstr: value, len: len) else { return 0 }
        nscript_event_await(script: script, subid: subid)
        let ev_handle: Int32 = 1
        stack_push_i32(interp, ev_handle);
        return BUILTIN_SUSPEND
        
    case .event_get_type:
        guard let event = script.event else {
            stack_push_i32(interp, 0);
            return 1
        }
        
        let type = NScriptEventType(resp: event)
        stack_push_i32(interp, Int32(type.rawValue));
        return 1
        
    case .event_get_note:
        guard let event = script.event, case .event = event
        else { stack_push_i32(interp, 0); return 1 }
        
        let note_handle: Int32 = 1
        stack_push_i32(interp, note_handle)
        return 1
        
    case .note_get_kind:
        guard let event = script.event, case .event(_, let note) = event
        else {
            stack_push_i32(interp, 0);
            return 1
            
        }
        
        stack_push_i32(interp, Int32(note.kind))
        return 1
        
    case .note_get_content:
        guard let event = script.event, case .event(_, let note) = event
        else { stack_push_i32(interp, 0); return 1 }
        
        stack_push_i32(interp, Int32(note.kind))
        return 1
    
    case .note_get_content_length:
        guard let event = script.event, case .event(_, let note) = event
        else { stack_push_i32(interp, 0); return 1 }
        
        stack_push_i32(interp, Int32(note.content.utf8.count))
        return 1
    }
    
}

func nscript_add_relay(script: NostrScript, relay: String) -> Bool {
    guard let url = RelayURL(relay) else { return false }
    let desc = RelayDescriptor(url: url, info: .rw, variant: .ephemeral)
    return (try? script.pool.add_relay(desc)) != nil
}


@_cdecl("nscript_set_bool")
public func nscript_set_bool(interp: UnsafeMutablePointer<wasm_interp>?, setting: UnsafePointer<UInt16>, setting_len: Int32, val: Int32) -> Int32 {
    
    guard let setting = asm_str(cstr: setting, len: setting_len),
          UserSettingsStore.bool_options.contains(setting)
    else {
        stack_push_i32(interp, 0);
        return 1;
    }
    
    let key = pk_setting_key(UserSettingsStore.pubkey ?? .empty, key: setting)
    let b = val > 0 ? true : false
    print("nscript setting bool setting \(setting) to \(b)")
    UserDefaults.standard.set(b, forKey: key)
    
    stack_push_i32(interp, 1);
    return 1;
}

@_cdecl("nscript_pool_send_to")
public func nscript_pool_send_to(interp: UnsafeMutablePointer<wasm_interp>?, preq: UnsafePointer<UInt16>, req_len: Int32, to: UnsafePointer<UInt16>, to_len: Int32) -> Int32 {

    guard let script = interp_nostrscript(interp: interp),
          let req_str = asm_str(cstr: preq, len: req_len),
          let to = asm_str(cstr: to, len: to_len),
          let to_relay_url = RelayURL(to)
    else {
        return 0
    }

    DispatchQueue.main.async {
        script.pool.send_raw(.custom(req_str), to: [to_relay_url], skip_ephemeral: false)
    }

    return 1;
}

func nscript_pool_send(script: NostrScript, req req_str: String) -> Int32 {
    //script.test("pool_send: '\(req_str)'")
    
    DispatchQueue.main.sync {
        script.pool.send_raw(.custom(req_str), skip_ephemeral: false)
    }
    
    return 1;
}

func nscript_event_await(script: NostrScript, subid: String)  {
    script.waiting_on = .event(subid)
}

func nscript_get_error_backtrace(errors: inout errors) -> [String] {
    var xs = [String]()
    var errs = cursor()
    var err = error()

    copy_cursor(&errors.cur, &errs)
    errs.p = errs.start;

    while (errs.p < errors.cur.p) {
        if (cursor_pull_error(&errs, &err) == 0) {
            return xs
        }
        
        xs.append(String(cString: err.msg))
    }
    
    return xs
}

func nscript_run(interp: inout wasm_interp, resuming: Bool) -> NostrScriptRunResult {
    var res: Int32 = 0
    var retval: Int32 = 0
        
    if (resuming) {
        print("resuming nostrscript");
        res = interp_wasm_module_resume(&interp, &retval);
    } else {
        res = interp_wasm_module(&interp, &retval);
    }
    
    if res == 0 {
        print_callstack(&interp);
        print_error_backtrace(&interp.errors);
        let backtrace = nscript_get_error_backtrace(errors: &interp.errors)
        return .runtime_err(backtrace)
    }
    
    if res == BUILTIN_SUSPEND {
        return .suspend
    }

    //print_stack(&interp.stack);
    wasm_interp_free(&interp);

    return .finished(Int(retval))
}

