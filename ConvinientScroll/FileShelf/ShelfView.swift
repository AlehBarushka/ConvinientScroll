import SwiftUI
import AppKit
import Combine

/// State of one display's shelf, driven by `ShelfPanelController`.
@MainActor
final class ShelfPanelModel: ObservableObject {
    @Published var mode: ShelfGeometry.Mode = .hidden
    @Published var isDropTargeted = false
    /// The card row exists only while this is true; it is released a moment after
    /// the shelf collapses so a collapsed shelf holds no thumbnails or views.
    @Published var showsContent = false
    @Published var selection = ShelfSelection()
    let geometry: ShelfGeometry

    init(geometry: ShelfGeometry) {
        self.geometry = geometry
    }
}

struct ShelfActions {
    var url: (ShelfItem) -> URL?
    var remove: (UUID) -> Void
    var clear: () -> Void
    var dragOutBegan: () -> Void
    var dragOutEnded: (_ accepted: Bool) -> Void
}

/// The black shape at the top of the screen and everything inside it.
struct ShelfRootView: View {
    @ObservedObject var model: ShelfPanelModel
    @ObservedObject var store: ShelfStore
    let actions: ShelfActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: ShelfGeometry { model.geometry }

    var body: some View {
        let shape = geometry.shape(for: model.mode)
        ZStack(alignment: .top) {
            NotchShape(earRadius: shape.earRadius, bottomRadius: shape.bottomRadius)
                .fill(Color.black.opacity(model.mode == .hidden ? 0.01 : 1))
                .shadow(color: .black.opacity(model.mode == .expanded ? 0.35 : 0), radius: 14, y: 6)

            Group {
                switch model.mode {
                case .hidden:
                    EmptyView()
                case .indicator, .peek:
                    CollapsedBadge(geometry: geometry, mode: model.mode, count: store.items.count)
                        .transition(.opacity)
                case .expanded:
                    if model.showsContent {
                        ShelfContent(model: model, store: store, actions: actions)
                            .padding(.horizontal, shape.earRadius)
                            .transition(Self.contentTransition)
                    }
                }
            }
            .clipShape(NotchShape(earRadius: shape.earRadius, bottomRadius: shape.bottomRadius))
        }
        .frame(width: shape.outerWidth, height: shape.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(animation, value: model.mode)
        .animation(animation, value: model.showsContent)
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    // The cards stand still while the shape shrinks, so on collapse they must be gone
    // before it has moved far, or they read as lagging behind it.
    private static let contentTransition: AnyTransition = {
        let fadeAndScale = AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        return .asymmetric(insertion: fadeAndScale, removal: fadeAndScale.animation(.easeOut(duration: 0.1)))
    }()
}

/// A rectangle hanging from the top edge, with rounded bottom corners and concave
/// "ears" where it meets the top of the screen, like the notch itself.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set { earRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4)
        let radius = min(bottomRadius, (rect.width - ear * 2) / 2, rect.height - ear)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear + radius, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear - radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The small badge: tray and count beside the notch, or a pill on other displays.
/// While a file is dragged close, a drop arrow grows out below.
private struct CollapsedBadge: View {
    let geometry: ShelfGeometry
    let mode: ShelfGeometry.Mode
    let count: Int

    private var closeness: Double {
        if case .peek(let value) = mode { value } else { 0 }
    }

    private var isPeeking: Bool {
        if case .peek = mode { true } else { false }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // During a drag the badge says "drop here"; otherwise it shows the tray.
                Image(systemName: isPeeking ? "tray.and.arrow.down.fill" : "tray.full.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: count)
                if geometry.hasNotch { Spacer(minLength: 0) }
                Text(count, format: .number)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .opacity(count > 0 ? 1 : 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, geometry.hasNotch ? 14 : 12)
            .frame(height: geometry.topBand)

            if closeness > 0 {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(0.6 + 0.4 * closeness)
                    .opacity(closeness)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
    }
}

/// Header and card row of the expanded shelf.
private struct ShelfContent: View {
    @ObservedObject var model: ShelfPanelModel
    @ObservedObject var store: ShelfStore
    let actions: ShelfActions
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.geometry.topBand)
            if store.items.isEmpty {
                DropPrompt(isTargeted: model.isDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.bottom, 10)
        .overlay {
            if model.isDropTargeted, !store.items.isEmpty {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .padding(EdgeInsets(top: model.geometry.topBand + 2, leading: 10, bottom: 8, trailing: 10))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let message = store.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                Label {
                    Text("Shelf")
                } icon: {
                    Image(systemName: "tray.full.fill")
                        .symbolEffect(.bounce, value: store.items.count)
                }
                .foregroundStyle(.white.opacity(0.85))
                if !store.items.isEmpty {
                    Text(store.items.count, format: .number)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Keep the header clear of the camera housing.
            Spacer(minLength: (model.geometry.notch?.width ?? 0) + 16)

            if !store.items.isEmpty {
                DragAllHandle(files: { allFiles }, onBegin: actions.dragOutBegan, onEnd: dragEnded)
                Button("Clear", action: actions.clear)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 18)
        .animation(.easeOut(duration: 0.2), value: store.failureMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.items.count)
    }

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                // Newest first: that is usually the file you came for.
                ForEach(Array(store.items.reversed().enumerated()), id: \.element.id) { index, item in
                    ShelfCard(
                        item: item,
                        url: actions.url(item),
                        isMissing: store.missingItemIDs.contains(item.id),
                        isSelected: model.selection.ids.contains(item.id),
                        appearDelay: Double(min(index, 10)) * 0.025,
                        actions: actions,
                        onClick: { flags in
                            model.selection.click(item.id, modifier: .init(flags: flags), order: selectableIDs)
                        },
                        dragFiles: { filesForDrag(from: item.id) },
                        onDragEnd: dragEnded
                    )
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: rowWidth, maxHeight: .infinity, alignment: .leading)
            .background(ShelfEmptySpaceClick { model.selection.clear() })
            .animation(.spring(response: 0.38, dampingFraction: 0.75), value: store.items.map(\.id))
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { rowWidth = $0 }
        .onChange(of: selectableIDs) { _, ids in model.selection.retain(Set(ids)) }
    }

    /// In the order the cards are shown.
    private var selectableIDs: [UUID] {
        store.items.reversed().map(\.id).filter { !store.missingItemIDs.contains($0) }
    }

    private var allFiles: [ShelfDragFile] {
        store.items.filter { !store.missingItemIDs.contains($0.id) }.compactMap(dragFile)
    }

    private func filesForDrag(from id: UUID) -> [ShelfDragFile] {
        let ids = model.selection.beginDrag(from: id, order: selectableIDs)
        return ids.compactMap { id in store.items.first { $0.id == id } }.compactMap(dragFile)
    }

    private func dragFile(for item: ShelfItem) -> ShelfDragFile? {
        actions.url(item).map { ShelfDragFile(url: $0, image: ThumbnailCache.shared.cached(item.id)) }
    }

    private func dragEnded(accepted: Bool) {
        if accepted { model.selection.clear() }
        actions.dragOutEnded(accepted)
    }
}

private struct DropPrompt: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 26, weight: .medium))
                .symbolEffect(.bounce, value: isTargeted)
                .scaleEffect(isTargeted ? 1.12 : 1)
            Text(isTargeted ? "Release to add" : "Drop files here")
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.opacity)
        }
        .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.6))
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isTargeted)
    }
}

private struct DragAllHandle: View {
    let files: () -> [ShelfDragFile]
    let onBegin: () -> Void
    let onEnd: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        Label("Drag All", systemImage: "square.stack.3d.up.fill")
            .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(isHovering ? 0.14 : 0.08), in: Capsule())
            .overlay(ShelfDragSource(files: files, onBegin: onBegin, onEnd: onEnd))
            .onHover { isHovering = $0 }
            .help("Drag every file on the shelf at once")
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    let url: URL?
    let isMissing: Bool
    let isSelected: Bool
    let appearDelay: Double
    let actions: ShelfActions
    let onClick: (NSEvent.ModifierFlags) -> Void
    let dragFiles: () -> [ShelfDragFile]
    let onDragEnd: (Bool) -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var hasAppeared = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let side: CGFloat = 60

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.08))
                }
            }
            .frame(width: Self.side, height: Self.side)
            .overlay(alignment: .bottomTrailing) { badge }
            .opacity(isMissing ? 0.4 : 1)

            Text(item.displayName)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 76)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if !isMissing, let url {
                ShelfDragSource(
                    files: dragFiles,
                    onBegin: actions.dragOutBegan,
                    onEnd: onDragEnd,
                    onClick: onClick,
                    onOpen: { NSWorkspace.shared.open(url) }
                )
            } else {
                // Keeps a click on an unavailable card from reaching the empty-space catcher.
                ShelfDragSource(files: { [] })
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    actions.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white.opacity(0.85))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isHovering ? 1.05 : 1)
        .scaleEffect(hasAppeared ? 1 : 0.85)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
        .help(helpText)
        .onAppear {
            thumbnail = ThumbnailCache.shared.cached(item.id)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.75).delay(appearDelay)) {
                hasAppeared = true
            }
        }
        .task(id: item.id) {
            guard thumbnail == nil, !isMissing, let url else { return }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item.id, url: url, side: Self.side, scale: displayScale)
        }
    }

    private var cardBackground: Color {
        isSelected ? Color(nsColor: .controlAccentColor).opacity(0.45) : .white.opacity(isHovering ? 0.1 : 0)
    }

    @ViewBuilder
    private var badge: some View {
        if isMissing {
            BadgeIcon(symbol: "exclamationmark.triangle.fill", tint: .yellow)
        } else if item.isReference {
            BadgeIcon(symbol: "link", tint: .orange)
        }
    }

    private var helpText: String {
        if isMissing { return "\(item.displayName) — the original is no longer available" }
        if item.isReference { return "\(item.displayName) — a link to the original on another disk" }
        return item.displayName
    }
}

private struct BadgeIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
            .offset(x: 4, y: 4)
    }
}
