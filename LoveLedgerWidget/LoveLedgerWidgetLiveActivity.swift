//
//  LoveLedgerWidgetLiveActivity.swift
//  LoveLedgerWidget
//
//  Created by Jackson Feng on 12/5/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LoveLedgerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LoveLedgerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoveLedgerWidgetAttributes.self) { context in
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

extension LoveLedgerWidgetAttributes {
    fileprivate static var preview: LoveLedgerWidgetAttributes {
        LoveLedgerWidgetAttributes(name: "World")
    }
}

extension LoveLedgerWidgetAttributes.ContentState {
    fileprivate static var smiley: LoveLedgerWidgetAttributes.ContentState {
        LoveLedgerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LoveLedgerWidgetAttributes.ContentState {
         LoveLedgerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LoveLedgerWidgetAttributes.preview) {
   LoveLedgerWidgetLiveActivity()
} contentStates: {
    LoveLedgerWidgetAttributes.ContentState.smiley
    LoveLedgerWidgetAttributes.ContentState.starEyes
}
