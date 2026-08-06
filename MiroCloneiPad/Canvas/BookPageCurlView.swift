import SwiftUI
import UIKit

/// Wraps UIKit's native `UIPageViewController(transitionStyle: .pageCurl)`
/// to provide hardware-accelerated 3D paper curling, real-time finger tracking,
/// realistic underside page shadows, and interactive drag gesture physics.
struct BookPageCurlView: UIViewControllerRepresentable {
    @ObservedObject var store: CanvasStore
    var pages: [PageLayout]
    var pageWidth: CGFloat
    var pageHeight: CGFloat

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

        let initialVC = context.coordinator.makeHostingController(for: store.currentPageIndex)
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

        func makeHostingController(for index: Int) -> PageHostingController {
            let total = max(parent.pages.count, 1)
            let safeIndex = min(max(index, 0), total - 1)
            let pageLayout = parent.pages[safeIndex]

            let rootView = AnyView(
                PageView(
                    store: parent.store,
                    pageLayout: pageLayout,
                    pageWidth: parent.pageWidth,
                    pageHeight: parent.pageHeight,
                    totalPages: total
                )
            )

            return PageHostingController(pageIndex: safeIndex, rootView: rootView)
        }

        func sync(uiViewController: UIPageViewController) {
            let safeIndex = min(max(parent.store.currentPageIndex, 0), max(parent.pages.count - 1, 0))
            if let visibleVC = uiViewController.viewControllers?.first as? PageHostingController {
                let total = max(parent.pages.count, 1)
                let pageLayout = parent.pages[safeIndex]
                visibleVC.pageIndex = safeIndex
                visibleVC.rootView = AnyView(
                    PageView(
                        store: parent.store,
                        pageLayout: pageLayout,
                        pageWidth: parent.pageWidth,
                        pageHeight: parent.pageHeight,
                        totalPages: total
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
            guard nextIndex < parent.pages.count else { return nil }
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
                    self.parent.store.currentPageIndex = visibleVC.pageIndex
                }
            }
        }
    }
}

/// Custom UIHostingController subclass that tracks page index for UIPageViewController navigation.
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
