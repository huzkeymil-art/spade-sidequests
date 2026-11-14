import SwiftUI

@main
struct SpadeApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 13 / 255, green: 15 / 255, blue: 12 / 255).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Spade").font(.custom("Jacquard24-Regular", size: 96))
                    Text("\(Content.quests.count) quests, \(Content.items.count) items").font(.custom("Jersey15-Regular", size: 15))
                    Text("Dig a little every day.").font(.custom("IM_FELL_English_Italic", size: 19))
                }
                .foregroundStyle(Color(red: 230 / 255, green: 223 / 255, blue: 200 / 255))
            }
        }
    }
}
