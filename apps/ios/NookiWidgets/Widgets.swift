import SwiftUI
import WidgetKit

@main
struct NookiWidgetBundle: WidgetBundle {
    var body: some Widget {
        CornerWidget()
        MochiWidget()
        BlockWidget()
        UsAccessoryWidget()
        PetMochiControl()
        NoteAccessoryWidget()
        NewNoteControl()
    }
}

/// Large: Mochi's room on top, two blocks of the couple's choice below.
struct CornerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.mikitahimpel.billet.corner", intent: CornerConfiguration.self,
                               provider: NookiProvider<CornerConfiguration>()) { entry in
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
            .containerBackground(WidgetInk.background, for: .widget)
        }
        .configurationDisplayName("Our Corner")
        .description("Mochi's room with two blocks of your choice.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Medium: Mochi next to the smart slot or a fixed block.
struct MochiWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.mikitahimpel.billet.mochi", intent: MochiConfiguration.self,
                               provider: NookiProvider<MochiConfiguration>()) { entry in
            HStack(spacing: 0) {
                Link(destination: DeepLink.room.url) { MochiRoom(snapshot: entry.snapshot, showsCaption: false) }
                Hairline(vertical: true)
                Block(slot: entry.configuration.slot, entry: entry)
            }
            .containerBackground(WidgetInk.background, for: .widget)
        }
        .configurationDisplayName("Billet")
        .description("Mochi and what matters right now.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// Small: one block. Medium: two side by side.
struct BlockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.mikitahimpel.billet.block", intent: ModuleConfiguration.self,
                               provider: NookiProvider<ModuleConfiguration>()) { entry in
            BlockWidgetView(entry: entry)
                .containerBackground(WidgetInk.background, for: .widget)
        }
        .configurationDisplayName("Block")
        .description("Mood, a list, a date idea, a countdown or a photo. Smart picks what matters now.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct BlockWidgetView: View {
    let entry: NookiEntry<ModuleConfiguration>
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
private struct Block<C: NookiConfiguration>: View {
    let slot: WidgetSlot
    let entry: NookiEntry<C>

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
        WidgetInk.hairline
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
