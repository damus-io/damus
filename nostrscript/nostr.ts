
// these are handles not actual pointers
export type Note = i32;
export type Event = i32;

export enum EventType {
  OK     = 1,
  NOTE   = 2,
  NOTICE = 3,
  EOSE   = 4
}

enum Command {
	POOL_SEND = 1,
	ADD_RELAY = 2,
	EVENT_AWAIT = 3,
	EVENT_GET_TYPE = 4,
	EVENT_GET_NOTE = 5,
	NOTE_GET_KIND = 6,
	NOTE_GET_CONTENT = 7,
	NOTE_GET_CONTENT_LENGTH = 8,
}

declare function nostr_log(log: string): void;
declare function nostr_cmd(cmd: i32, val: i32, len: i32): i32;
declare function nostr_pool_send_to(req: string, req_len: i32, to: string, to_len: i32): void;
declare function nostr_set_bool(key: string, key_len: i32, val: i32): i32;

export function pool_send(req: string): void {
	nostr_cmd(Command.POOL_SEND, changetype<i32>(req), req.length)
}

export function pool_send_to(req: string, to: string): void {
	return nostr_pool_send_to(req, req.length, to, to.length)
}

export function pool_add_relay(relay: string): boolean {
	let ok = nostr_cmd(Command.ADD_RELAY, changetype<i32>(relay), relay.length)
	return ok as boolean
}

export function event_await(subid: string): Event {
	return nostr_cmd(Command.EVENT_AWAIT, changetype<i32>(subid), subid.length) as i32
}

export function event_get_type(ev: Event): EventType {
	if (!ev) return 0;
	return nostr_cmd(Command.EVENT_GET_TYPE, ev, 0) as EventType
}

export function event_get_note(ev: Event): Note {
	if (!ev) return 0;
	return nostr_cmd(Command.EVENT_GET_NOTE, ev, 0)
}

export function set_bool_setting(setting: string, value: boolean): i32 {
	return nostr_set_bool(setting, setting.length, value)
}

export function note_get_kind(note: Note): u32 {
	if (!note) return 0;
	return nostr_cmd(Command.NOTE_GET_KIND, note, 0);
}

function note_get_content_length(): i32 {
	return nostr_cmd(Command.NOTE_GET_CONTENT_LENGTH, note, 0)
}

export function log(log: string): void {
	nostr_log(log)
}

export function note_get_content(): string {
	let res = nostr_cmd(Command.NOTE_GET_CONTENT, note, 0);
	if (!res) return "";

	let len = note_get_content_length()
	let codes = TypedArray.wrap()

	return String.fromCharCodes(codes)
}

