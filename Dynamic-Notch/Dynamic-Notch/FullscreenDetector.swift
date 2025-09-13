//
//  FullscreenDetector.swift 업데이트
//  Dynamic-Notch
//


//import Cocoa
//import SwiftUI
//import Combine
//import MacroVisionKit
//
//class FullscreenDetector: ObservableObject {
//    static let shared = FullscreenDetector()
//    
//    @Published var isFullscreenActive: Bool = false
//    @Published var shouldHideNotch: Bool = false
//    @Published var currentFullscreenApp: NSRunningApplication?
//    
//    private let detector: MacroVisionKit
//    private var cancellables = Set<AnyCancellable>()
//    private var monitoringTimer: Timer?
//    
//    private init() {
//        self.detector = MacroVisionKit.shared
//        detector.configuration.includeSystemApps = true
//        
//        setupMonitoring()
//        
//        // isFullscreenActive가 변경되면 shouldHideNotch도 업데이트
//        $isFullscreenActive
//            .assign(to: \.shouldHideNotch, on: self)
//            .store(in: &cancellables)
//    }
//    
//    deinit {
//        stopMonitoring()
//        cancellables.removeAll()
//    }
//    
//    private func setupMonitoring() {
//        // 워크스페이스 알림 관찰
//        let notificationCenter = NSWorkspace.shared.notificationCenter
//        
//        // 앱 활성화/비활성화 감지
//        notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
//            .sink { [weak self] _ in
//                self?.checkFullscreenStatus()
//            }
//            .store(in: &cancellables)
//        
//        notificationCenter.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
//            .sink { [weak self] _ in
//                self?.checkFullscreenStatus()
//            }
//            .store(in: &cancellables)
//        
//        // 화면 변경 감지
//        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
//            .sink { [weak self] _ in
//                self?.checkFullscreenStatus()
//            }
//            .store(in: &cancellables)
//        
//        // 스페이스 변경 감지
//        notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
//            .sink { [weak self] _ in
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    self?.checkFullscreenStatus()
//                }
//            }
//            .store(in: &cancellables)
//        
//        // 주기적 모니터링
//        startPeriodicMonitoring()
//    }
//    
//    private func startPeriodicMonitoring() {
//        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
//            self?.checkFullscreenStatus()
//        }
//    }
//    
//    private func stopMonitoring() {
//        monitoringTimer?.invalidate()
//        monitoringTimer = nil
//    }
//    
//    private func checkFullscreenStatus() {
//        DispatchQueue.main.async {
//            let fullscreenApps = self.detector.detectFullscreenApps(debug: false)
//            let frontmostApp = NSWorkspace.shared.frontmostApplication
//            
//            // 현재 활성 앱이 전체화면인지 확인
//            let isCurrentAppFullscreen = fullscreenApps.contains { fullscreenApp in
//                guard let frontmost = frontmostApp else { return false }
//                return fullscreenApp.bundleIdentifier == frontmost.bundleIdentifier
//            }
//            
//            // 상태 업데이트
//            if self.isFullscreenActive != isCurrentAppFullscreen {
//                self.isFullscreenActive = isCurrentAppFullscreen
//                self.currentFullscreenApp = isCurrentAppFullscreen ? frontmostApp : nil
//                
//                print(isCurrentAppFullscreen ?
//                      "전체화면 감지됨: \(frontmostApp?.localizedName ?? "Unknown")" :
//                      "전체화면 해제됨")
//            }
//        }
//    }
//}
//
//// MacroVisionKit 프레임워크가 없는 경우를 위한 Mock 구현
//#if !canImport(MacroVisionKit)
//// MacroVisionKit이 없는 경우의 대체 구현
//struct MockMacroVisionApp {
//    let bundleIdentifier: String?
//    let debugDescription: String
//}
//
//class MockMacroVisionKit {
//    static let shared = MockMacroVisionKit()
//    
//    struct Configuration {
//        var includeSystemApps: Bool = false
//    }
//    
//    var configuration = Configuration()
//    
//    func detectFullscreenApps(debug: Bool) -> [MockMacroVisionApp] {
//        // 메뉴바가 숨겨져 있으면 전체화면으로 간주하는 간단한 구현
//        guard !NSMenu.menuBarVisible() else { return [] }
//        
//        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
//            return [MockMacroVisionApp(
//                bundleIdentifier: frontmostApp.bundleIdentifier,
//                debugDescription: frontmostApp.localizedName ?? "Unknown"
//            )]
//        }
//        
//        return []
//    }
//}
import Cocoa
import SwiftUI
import Combine

class FullscreenDetector: ObservableObject {
    static let shared = FullscreenDetector()
    
    @Published var isFullscreenActive: Bool = false
    @Published var shouldHideNotch: Bool = false
    @Published var currentFullscreenApp: NSRunningApplication?
    
    private var cancellables = Set<AnyCancellable>()
    private var quickCheckTimer: Timer?
    
    // 🚀 즉시 반응을 위한 캐시
    private var lastMenuBarState: Bool = true
    private var lastFrontmostApp: NSRunningApplication?
    private var isProcessingStateChange = false
    
    private init() {
        setupInstantDetection()
        setupQuickPolling()
    }
    
    // MARK: - 즉시 감지 설정
    private func setupInstantDetection() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        
        // 🎯 앱 활성화 - 즉시 반응 (지연 없음)
        notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // 🚀 백그라운드에서 빠른 체크
            DispatchQueue.global(qos: .userInteractive).async {
                let result = self.quickFullscreenCheck()
                
                DispatchQueue.main.async {
                    self.updateStateIfChanged(result)
                }
            }
        }
        
        // 🎯 앱 비활성화 - 즉시 반응
        notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 비활성화 시에는 거의 확실히 전체화면이 아님
            self?.updateStateIfChanged(false)
        }
        
        // 🎯 스페이스 변경 - 즉시 반응
        notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 스페이스 변경 시 즉시 체크
            self?.performQuickCheck()
        }
        
        // 🎯 화면 파라미터 변경
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performQuickCheck()
        }
    }
    
    // MARK: - 초고속 폴링 (보험용)
    private func setupQuickPolling() {
        // 매우 빠른 폴링 (100ms) - 이벤트가 놓칠 수 있는 경우를 대비
        quickCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.performQuickCheck()
        }
    }
    
    // MARK: - 고속 전체화면 체크
    private func performQuickCheck() {
        guard !isProcessingStateChange else { return }
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let result = self.quickFullscreenCheck()
            
            DispatchQueue.main.async {
                self.updateStateIfChanged(result)
            }
        }
    }
    
    // MARK: - 최적화된 전체화면 감지
    private func quickFullscreenCheck() -> Bool {
        // 1️⃣ 메뉴바 상태 체크 (가장 빠름)
        let menuBarHidden = !NSMenu.menuBarVisible()
        
        // 2️⃣ 현재 앱 체크
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        // 3️⃣ 제외할 앱들 필터링
        let excludedApps: Set<String> = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.systemuiserver"
        ]
        
        if excludedApps.contains(bundleId) {
            return false
        }
        
        // 4️⃣ 빠른 전체화면 판단
        if menuBarHidden {
            return true
        }
        
        // 5️⃣ 윈도우 크기 체크 (필요한 경우만)
        return hasFullscreenWindow(for: frontmostApp)
    }
    
    // MARK: - 윈도우 크기 체크 (최적화됨)
    private func hasFullscreenWindow(for app: NSRunningApplication) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        // CGWindowList를 사용한 빠른 체크
        let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        for windowInfo in windowInfos {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == app.processIdentifier,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            
            let windowWidth = bounds["Width"] ?? 0
            let windowHeight = bounds["Height"] ?? 0
            
            // 화면 크기의 95% 이상이면 전체화면으로 간주
            if windowWidth >= screen.frame.width * 0.95 &&
               windowHeight >= screen.frame.height * 0.95 {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - 상태 업데이트 (중복 방지)
    private func updateStateIfChanged(_ newState: Bool) {
        guard !isProcessingStateChange && newState != isFullscreenActive else { return }
        
        isProcessingStateChange = true
        
        // 🎯 즉시 상태 업데이트 (애니메이션 없음)
        isFullscreenActive = newState
        shouldHideNotch = newState
        currentFullscreenApp = newState ? NSWorkspace.shared.frontmostApplication : nil
        
        print("⚡ 즉시 전체화면 상태 변경: \(newState)")
        
        // 짧은 지연 후 플래그 리셋
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isProcessingStateChange = false
        }
    }
    
    deinit {
        quickCheckTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
