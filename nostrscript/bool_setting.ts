
import * as nostr from './nostr'

export function go(): i32 {
	var setting = "mny`or"
	var new_setting = ""
	for (let i = 0; i < setting.length; i++) {
		new_setting += String.fromCharCode(setting.charCodeAt(i) + 1);
	}
	// this should fail
	if (nostr.set_bool_setting("shmorg", true)) {
		// you shouldn't be able to set settings that dont exist
		return 0;
	}
	return nostr.set_bool_setting(new_setting, false)
}

go()
