//
//  ScoffieCookActivityLiveActivity.swift
//  ScoffieCookActivity
//
//  Created by Rafi on 01/10/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ScoffieCookActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ScoffieCookActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoffieCookActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ScoffieCookActivityAttributes {
    fileprivate static var preview: ScoffieCookActivityAttributes {
        ScoffieCookActivityAttributes(name: "World")
    }
}

extension ScoffieCookActivityAttributes.ContentState {
    fileprivate static var smiley: ScoffieCookActivityAttributes.ContentState {
        ScoffieCookActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ScoffieCookActivityAttributes.ContentState {
         ScoffieCookActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ScoffieCookActivityAttributes.preview) {
   ScoffieCookActivityLiveActivity()
} contentStates: {
    ScoffieCookActivityAttributes.ContentState.smiley
    ScoffieCookActivityAttributes.ContentState.starEyes
}
