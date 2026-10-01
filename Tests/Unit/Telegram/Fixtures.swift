//  Raw TDLib JSON fixtures.
//
//  Built as JSON rather than through TDLibKit's memberwise initialisers on
//  purpose: it exercises the real decoding path, so a test that passes here
//  proves the same bytes TDLib sends would produce the same result.

import Foundation
import TDLibKit
@testable import NodogramTelegram

enum Fixture {

    static func update(_ json: String) throws -> Update {
        try TelegramGateway.decodeUpdate(Data(json.utf8))
    }

    static func position(list: String = "chatListMain", order: Int64, pinned: Bool = false) -> String {
        #"{"@type":"chatPosition","list":{"@type":"\#(list)"},"order":"\#(order)","is_pinned":\#(pinned)}"#
    }

    static func chatType(_ kind: String, id: Int64 = 0) -> String {
        switch kind {
        case "private": return #"{"@type":"chatTypePrivate","user_id":\#(id)}"#
        case "group": return #"{"@type":"chatTypeSupergroup","supergroup_id":\#(id),"is_channel":false}"#
        case "channel": return #"{"@type":"chatTypeSupergroup","supergroup_id":\#(id),"is_channel":true}"#
        default: return #"{"@type":"chatTypeBasicGroup","basic_group_id":\#(id)}"#
        }
    }

    static func newChat(
        id: Int64,
        title: String,
        type: String = #"{"@type":"chatTypeBasicGroup","basic_group_id":1}"#,
        positions: [String] = [],
        unread: Int = 0,
        lastReadOutbox: Int64 = 0,
        muteFor: Int = 0,
        lastMessage: String? = nil
    ) -> String {
        """
        {"@type":"updateNewChat","chat":{"@type":"chat",
         "id":\(id),"type":\(type),"title":"\(title)",
         "accent_color_id":0,"profile_accent_color_id":-1,
         "background_custom_emoji_id":"0","profile_background_custom_emoji_id":"0",
         "available_reactions":{"@type":"chatAvailableReactionsAll","max_reaction_count":11},
         "can_be_deleted_for_all_users":false,"can_be_deleted_only_for_self":true,"can_be_reported":false,
         "chat_lists":[],"client_data":"","default_disable_notification":false,
         "has_protected_content":false,"has_scheduled_messages":false,"has_welcome_messages":false,
         "is_marked_as_unread":false,"is_translatable":false,
         "last_read_inbox_message_id":0,"last_read_outbox_message_id":\(lastReadOutbox),
         "message_auto_delete_time":0,"reply_markup_message_id":0,
         "unread_count":\(unread),"unread_mention_count":0,"unread_poll_vote_count":0,"unread_reaction_count":0,
         "view_as_topics":false,
         "positions":[\(positions.joined(separator: ","))],
         \(lastMessage.map { #""last_message":\#($0),"# } ?? "")
         "notification_settings":{"@type":"chatNotificationSettings",
           "use_default_mute_for":\(muteFor == 0),"mute_for":\(muteFor),
           "use_default_sound":true,"sound_id":"0","use_default_show_preview":true,"show_preview":true,
           "use_default_mute_stories":true,"mute_stories":false,"use_default_story_sound":true,"story_sound_id":"0",
           "use_default_show_story_poster":true,"show_story_poster":false,
           "use_default_disable_pinned_message_notifications":true,"disable_pinned_message_notifications":false,
           "use_default_disable_mention_notifications":true,"disable_mention_notifications":false},
         "permissions":{"@type":"chatPermissions","can_send_basic_messages":true,"can_send_audios":true,
           "can_send_documents":true,"can_send_photos":true,"can_send_videos":true,"can_send_video_notes":true,
           "can_send_voice_notes":true,"can_send_polls":true,"can_send_other_messages":true,
           "can_add_link_previews":true,"can_change_info":true,"can_invite_users":true,"can_pin_messages":true,
           "can_create_topics":true,"can_react_to_messages":true,"can_edit_tag":true},
         "video_chat":{"@type":"videoChat","group_call_id":0,"has_participants":false}
        }}
        """
    }

    static func text(_ value: String) -> String {
        #"{"@type":"messageText","text":{"@type":"formattedText","text":"\#(value)","entities":[]}}"#
    }

    static func message(
        id: Int64,
        chatId: Int64,
        senderUserId: Int64 = 7,
        outgoing: Bool = false,
        date: Int = 1_760_000_000,
        content: String
    ) -> String {
        """
        {"@type":"message","id":\(id),"chat_id":\(chatId),
         "sender_id":{"@type":"messageSenderUser","user_id":\(senderUserId)},
         "is_outgoing":\(outgoing),"is_pinned":false,"is_from_offline":false,"can_be_saved":true,
         "has_timestamped_media":false,"is_channel_post":false,"is_paid_star_suggested_post":false,
         "is_paid_gram_suggested_post":false,"contains_unread_mention":false,"contains_unread_poll_votes":false,
         "date":\(date),"edit_date":0,"unread_reactions":[],"chat_instance":"0",
         "ephemeral_message_id":0,"sender_boost_count":0,"paid_message_star_count":0,
         "author_signature":"","media_album_id":"0","effect_id":"0","via_bot_user_id":0,
         "sender_business_bot_user_id":0,"self_destruct_in":0,"auto_delete_in":0,
         "sender_tag":"","summary_language_code":"",
         "content":\(content)}
        """
    }

    static func user(id: Int64, first: String, last: String = "", status: String = #"{"@type":"userStatusRecently","by_my_privacy_settings":false}"#) -> String {
        """
        {"@type":"updateUser","user":{"@type":"user","id":\(id),"first_name":"\(first)","last_name":"\(last)",
         "phone_number":"","status":\(status),"accent_color_id":0,"profile_accent_color_id":-1,
         "background_custom_emoji_id":"0","profile_background_custom_emoji_id":"0",
         "is_contact":false,"is_mutual_contact":false,"is_close_friend":false,"is_premium":false,
         "is_support":false,"have_access":true,"restricts_new_chats":false,"paid_message_star_count":0,
         "added_to_attachment_menu":false,"language_code":"en",
         "type":{"@type":"userTypeRegular"}}}
        """
    }
}
