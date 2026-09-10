//
//  DailySpendWidgetLiveActivity.swift
//  DailySpendWidget
//
//  Created by Jackson Feng on 12/5/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DailySpendWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DailySpendWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailySpendWidgetAttributes.self) { context in
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
            .keylineTint(Color.red)
        }
    }
}

extension DailySpendWidgetAttributes {
    fileprivate static var preview: DailySpendWidgetAttributes {
        DailySpendWidgetAttributes(name: "World")
    }
}

extension DailySpendWidgetAttributes.ContentState {
    fileprivate static var smiley: DailySpendWidgetAttributes.ContentState {
        DailySpendWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DailySpendWidgetAttributes.ContentState {
         DailySpendWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DailySpendWidgetAttributes.preview) {
   DailySpendWidgetLiveActivity()
} contentStates: {
    DailySpendWidgetAttributes.ContentState.smiley
    DailySpendWidgetAttributes.ContentState.starEyes
}
