import SwiftUI
import UIKit

/// Wraps UIKit's native `UIPageViewController(transitionStyle: .pageCurl)`
/// to navigate book spreads (`BookSpreadView`). Supports single-page mode on iPhone
/// and 2-page open book spread mode on iPad.
struct BookPageCurlView: UIViewControllerRepresentable {
    @ObservedObject var store: CanvasStore
    var spreads: [BookSpread]
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var totalPages: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator

        let currentSpreadIndex = store.currentPageIndex
        let initialVC = context.coordinator.makeHostingController(for: currentSpreadIndex)
        pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)

        return pageViewController
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(uiViewController: uiViewController)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: BookPageCurlView

        init(_ parent: BookPageCurlView) {
            self.parent = parent
        }

        func makeHostingController(for spreadIndex: Int) -> PageHostingController {
            let totalSpreads = max(parent.spreads.count, 1)
            let safeIndex = min(max(spreadIndex, 0), totalSpreads - 1)
            let spread = parent.spreads[safeIndex]

            let rootView = AnyView(
                BookSpreadView(
                    store: parent.store,
                    spread: spread,
                    pageWidth: parent.pageWidth,
                    pageHeight: parent.pageHeight,
                    totalPages: parent.totalPages
                )
            )

            return PageHostingController(pageIndex: safeIndex, rootView: rootView)
        }

        func sync(uiViewController: UIPageViewController) {
            let targetSpreadIndex = parent.store.currentPageIndex
            let safeIndex = min(max(targetSpreadIndex, 0), max(parent.spreads.count - 1, 0))

            if let visibleVC = uiViewController.viewControllers?.first as? PageHostingController {
                let spread = parent.spreads[safeIndex]
                visibleVC.pageIndex = safeIndex
                visibleVC.rootView = AnyView(
                    BookSpreadView(
                        store: parent.store,
                        spread: spread,
                        pageWidth: parent.pageWidth,
                        pageHeight: parent.pageHeight,
                        totalPages: parent.totalPages
                    )
                )
            } else {
                let initialVC = makeHostingController(for: safeIndex)
                uiViewController.setViewControllers([initialVC], direction: .forward, animated: false)
            }
        }

        // MARK: - UIPageViewControllerDataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let hc = viewController as? PageHostingController else { return nil }
            let prevIndex = hc.pageIndex - 1
            guard prevIndex >= 0 else { return nil }
            return makeHostingController(for: prevIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let hc = viewController as? PageHostingController else { return nil }
            let nextIndex = hc.pageIndex + 1
            guard nextIndex < parent.spreads.count else { return nil }
            return makeHostingController(for: nextIndex)
        }

        // MARK: - UIPageViewControllerDelegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            if completed,
               let visibleVC = pageViewController.viewControllers?.first as? PageHostingController {
                DispatchQueue.main.async {
                    let newPageIndex = visibleVC.pageIndex
                    self.parent.store.currentPageIndex = newPageIndex
                }
            }
        }
    }
}

/// Custom UIHostingController subclass that tracks page/spread index for UIPageViewController navigation.
final class PageHostingController: UIHostingController<AnyView> {
    var pageIndex: Int

    init(pageIndex: Int, rootView: AnyView) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        self.view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
