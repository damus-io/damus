//
//  UserStatus.swift
//  damus
//
//  Created by William Casarin on 2023-08-22.
//

import Foundation
import MediaPlayer

struct Song {
    let started_playing: Date
    let content: String


}

struct UserStatus {
    let type: UserStatusType
    let expires_at: Date?
    let content: String

    func to_note(keypair: FullKeypair) -> NostrEvent? {
        return make_user_status_note(status: self, keypair: keypair)
    }

    init(type: UserStatusType, expires_at: Date?, content: String) {
        self.type = type
        self.expires_at = expires_at
        self.content = content
    }

    init?(ev: NostrEvent) {
        guard let tag = ev.referenced_params.just_one() else {
            return nil
        }

        let str = tag.param.string()
        if str == "general" {
            self.type = .general
        } else if str == "music" {
            self.type = .music
        } else {
            return nil
        }

        if let tag = ev.tags.first(where: { t in t.count >= 2 && t[0].matches_str("expiration") }),
           tag.count == 2,
           let expires = UInt32(tag[1].string())
        {
            self.expires_at = Date(timeIntervalSince1970: TimeInterval(expires))
        } else {
            self.expires_at = nil
        }

        self.content = ev.content
    }

}

enum UserStatusType: String {
    case music
    case general

}

class UserStatusModel: ObservableObject {
    @Published var general: UserStatus?
    @Published var music: UserStatus?

    func update_status(_ s: UserStatus) {
        switch s.type {
        case .music:
            self.music = s
        case .general:
            self.general = s
        }
    }

    var _playing_enabled: Bool
    var playing_enabled: Bool {
        set {
            var new_val = newValue

            if newValue {
                MPMediaLibrary.requestAuthorization { astatus in
                    switch astatus {
                    case .notDetermined: new_val = false
                    case .denied:        new_val = false
                    case .restricted:    new_val = false
                    case .authorized:    new_val = true
                    @unknown default:
                        new_val = false
                    }

                }
            }

            if new_val != playing_enabled {
                _playing_enabled = new_val
                self.objectWillChange.send()
            }
        }

        get {
            return _playing_enabled
        }
    }

    init(playing: UserStatus? = nil, status: UserStatus? = nil) {
        self.general = status
        self.music = playing
        self._playing_enabled = false
        self.playing_enabled = false
    }

    static var current_track: String? {
        let player = MPMusicPlayerController.systemMusicPlayer
        guard let nowPlayingItem = player.nowPlayingItem else { return nil }
        return nowPlayingItem.title
    }
}

func make_user_status_note(status: UserStatus, keypair: FullKeypair, expiry: Date? = nil) -> NostrEvent?
{
    var tags: [[String]] = [ ["d", status.type.rawValue] ]

    if let expiry {
        tags.append(["expiration", String(UInt32(expiry.timeIntervalSince1970))])
    } else if let expiry = status.expires_at  {
        tags.append(["expiration", String(UInt32(expiry.timeIntervalSince1970))])
    }

    let kind = NostrKind.status.rawValue
    guard let ev = NostrEvent(content: status.content, keypair: keypair.to_keypair(), kind: kind, tags: tags) else {
        return nil
    }

    return ev
}

