//
//  SimpleMediaRemoteController.swift
//  Dynamic-Notch
//
//  Created by PeterPark on 8/5/25.
//

import Foundation
import Combine

class SimpleMediaRemoteController: ObservableObject {
    
    //MARK: 속성들(음악재생에 필요한 변수)
    @Published var songTitle: String = ""
    @Published var artistName: String = ""
    @Published var isPlaying: Bool = false
    @Published var albumArtwork: Data? = nil
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0  //추가: 실시간 재생 시간
    @Published var bundleIdentifier: String = ""
    
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = ""
    
    init?() {
        guard setupMediaRemoteAdapter() else {
            print("MediaRemote Adapter를 설정할 수 없습니다")
            return nil
        }
        
        print("MediaRemote Adapter 초기화 성공")
        updateNowPlayingInfo()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupMediaRemoteAdapter() -> Bool {
        // Bundle에서 스크립트와 프레임워크 경로 찾기
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            print("mediaremote-adapter.pl 또는 프레임워크를 찾을 수 없음")
            return false
        }
        
        // 스트림 모드로 실행 (실시간 업데이트)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            scriptURL.path,
            frameworkPath,
            "stream",
            "--debounce=50" // 50ms 디바운스로 스팸 방지
        ]
        
        //데이터 통신 담당
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        self.process = process
        self.pipe = pipe
        
         //출력 읽기 핸들러 설정
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            
            if let chunk = String(data: data, encoding: .utf8) {
                self.buffer.append(chunk)
                self.processBuffer()
            }
        }
        
        // 프로세스 실행
        do {
            try process.run()
            return true
        } catch {
            print("❌ MediaRemote Adapter 실행 실패: \(error)")
            return false
        }
    }
    
    private func processBuffer() {
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            
            if !line.isEmpty {
                processAdapterOutput(line)
            }
        }
    }
    
    private func processAdapterOutput(_ jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else {
            return
        }
        
        let isDiff = object["diff"] as? Bool ?? false
        
        DispatchQueue.main.async { [weak self] in
            self?.updateFromPayload(payload, isDiff: isDiff)
        }
    }
    
    private func updateFromPayload(_ payload: [String: Any], isDiff: Bool) {
        // 제목
        if let title = payload["title"] as? String, !title.isEmpty {
            self.songTitle = title
        } else if !isDiff {
            self.songTitle = ""
        }
        
        // 아티스트
        if let artist = payload["artist"] as? String {
            self.artistName = artist
        
        } else if !isDiff {
            self.artistName = ""
        }
        
        // 재생 상태
        if let playing = payload["playing"] as? Bool {
            if self.isPlaying != playing {
                self.isPlaying = playing
            }
        } else if !isDiff {
            self.isPlaying = false
        }
        
        // 총 재생 시간
        if let duration = payload["duration"] as? Double {
            if self.duration != duration {
                self.duration = duration
               
            }
        } else if !isDiff {
            self.duration = 0
        }
        
        if let elapsedTime = payload["elapsedTime"] as? Double {
            if abs(self.currentTime - elapsedTime) > 1.0 { // 1초 이상 차이날 때만 업데이트 (자연스러운 흐름)
                self.currentTime = elapsedTime
                
            }
        } else if !isDiff {
            self.currentTime = 0
        }
        
        // 번들 식별자
        if let bundleId = payload["parentApplicationBundleIdentifier"] as? String ??
                           payload["bundleIdentifier"] as? String {
            self.bundleIdentifier = bundleId
        } else if !isDiff {
            self.bundleIdentifier = ""
        }
        
        // 앨범 아트
        if let artworkDataString = payload["artworkData"] as? String {
            self.albumArtwork = Data(base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if !isDiff {
            self.albumArtwork = nil
        }
    }
    
    // MARK: - Public Methods
    @objc func updateNowPlayingInfo() {
        executeCommand("get")
    }
    
    @objc func updatePlayingState() {
        updateNowPlayingInfo()
    }
    
    // MARK: - 제어 함수들
    func play() {
        executeCommand("send", parameters: ["0"]) // kMRPlay = 0
    }
    
    func pause() {
        executeCommand("send", parameters: ["1"]) // kMRPause = 1
    }
    
    func togglePlayPause() {
        executeCommand("send", parameters: ["2"]) // kMRTogglePlayPause = 2
    }
    
    func nextTrack() {
        executeCommand("send", parameters: ["4"]) // kMRNextTrack = 4
    }
    
    func previousTrack() {
        executeCommand("send", parameters: ["5"]) // kMRPreviousTrack = 5
    }
    
    func seek(to time: TimeInterval) {
        
    }
    
    // MARK: - Private Methods
    private func executeCommand(_ command: String, parameters: [String] = []) {
        
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            print("❌ 스크립트 또는 프레임워크 경로를 찾을 수 없음")
            return
        }
        
        // 별도 프로세스로 명령 실행
        let commandProcess = Process()
        commandProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        
        var arguments = [scriptURL.path, frameworkPath, command]
        arguments.append(contentsOf: parameters)
        commandProcess.arguments = arguments
        
        
        // 에러 출력 캡처
        let errorPipe = Pipe()
        commandProcess.standardError = errorPipe
        
        do {
            try commandProcess.run()
            commandProcess.waitUntilExit()
            
            let exitCode = commandProcess.terminationStatus
//            print("🔍 프로세스 종료 코드: \(exitCode)")
            
            if exitCode != 0 {
                // 에러 메시지 읽기
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                    
                }
            } else {
            }
        } catch {
            
        }
    }
    
    private func cleanup() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        
        if let process = process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        
        process = nil
        pipe = nil
    }
    
    // MARK: - Helper Functions
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
