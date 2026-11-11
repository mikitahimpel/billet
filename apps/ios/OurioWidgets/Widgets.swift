import MomentsInterface
import OurioShared
import SwiftUI
import Design
import UsInterface
import WidgetKit

@main
struct OurioWidgetBundle: WidgetBundle {
    var body: some Widget {
        CornerWidget()
        MochiWidget()
        BlockWidget()
        UsAccessoryWidget()
        PetMochiControl()
        NoteAccessoryWidget()
        NewNoteControl()
        DrawingWidget()
        DrawingLiveActivity()
    }
}

/// Large: Mochi's room on top, two blocks of the couple's choice below.
struct CornerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.ourio.app.corner", intent: CornerConfiguration.self,
                               provider: OurioProvider<CornerConfiguration>()) { entry in
            VStack(spacing: 0) {
                Link(destination: DeepLink.room.url) { MochiRoom(snapshot: entry.snapshot) }
                    .frame(maxHeight: .infinity)
                Hairline()
                HStack(spacing: 0) {
                    Block(slot: entry.configuration.left, entry: entry)
                    Hairline(vertical: true)
                    Block(slot: entry.configuration.right, entry: entry)
                }
                .frame(height: 158)
            }
            .containerBackground(Ink.screen, for: .widget)
        }
        .configurationDisplayName("Our Corner")
        .description("Your cat's room with two blocks of your choice.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Medium: Mochi next to the smart slot or a fixed block.
struct MochiWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.ourio.app.mochi", intent: MochiConfiguration.self,
                               provider: OurioProvider<MochiConfiguration>()) { entry in
            HStack(spacing: 0) {
                Link(destination: DeepLink.room.url) { MochiRoom(snapshot: entry.snapshot, showsCaption: false) }
                Hairline(vertical: true)
                Block(slot: entry.configuration.slot, entry: entry)
            }
            .containerBackground(Ink.screen, for: .widget)
        }
        .configurationDisplayName("Ourio")
        .description("Your cat and what matters right now.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// Small: one block. Medium: two side by side.
struct BlockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.ourio.app.block", intent: ModuleConfiguration.self,
                               provider: OurioProvider<ModuleConfiguration>()) { entry in
            BlockWidgetView(entry: entry)
                .containerBackground(Ink.screen, for: .widget)
        }
        .configurationDisplayName("Block")
        .description("Mood, a list, a date idea, a countdown or a photo. Smart picks what matters now.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct BlockWidgetView: View {
    let entry: OurioEntry<ModuleConfiguration>
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            let module = entry.configuration.first.module(in: entry.snapshot)
            ModuleView(module: module, snapshot: entry.snapshot, smart: entry.configuration.first == .smart,
                       momentImage: entry.momentImage)
                .widgetURL(module.link(in: entry.snapshot).url)
        } else {
            HStack(spacing: 0) {
                Block(slot: entry.configuration.first, entry: entry)
                Hairline(vertical: true)
                Block(slot: entry.configuration.second, entry: entry)
            }
        }
    }
}

/// A configured slot inside a bigger widget, linked to its own screen.
private struct Block<C: OurioConfiguration>: View {
    let slot: WidgetSlot
    let entry: OurioEntry<C>

    var body: some View {
        let module = slot.module(in: entry.snapshot)
        Link(destination: module.link(in: entry.snapshot).url) {
            ModuleView(module: module, snapshot: entry.snapshot, smart: slot == .smart, momentImage: entry.momentImage)
        }
    }
}

private struct Hairline: View {
    var vertical = false

    var body: some View {
        Ink.separator
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
