// Copyright 2016 Cisco Systems Inc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import AVFoundation

/// Represents a Spark phone device.
public class Phone {
    
    /// Privacy control of media access type.
    public enum MediaAccessType {
        /// Access to microphone.
        case audio
        /// Access to camera.
        case video
        /// Access to both microphone and camera.
        case audioVideo
    }

    /// Default camera facing mode, used as the default when dialing or answering a call.
    ///
    /// - note: The setting is not persistent
    @available(*, deprecated, message: "Use PhoneSettings.defaultFacingMode instead")
    public var defaultFacingMode: Call.FacingMode {
        get {
            return PhoneSettings.defaultFacingMode
        }
        set {
            PhoneSettings.defaultFacingMode = newValue
        }
    }
    
    /// Default loud speaker mode, used as the default when dialing or answering a call.
    /// True as using loud speaker, False as not.
    ///
    /// - note: The setting is not persistent.
    @available(*, deprecated, message: "Use PhoneSettings.defaultLoudSpeaker instead")
    public var defaultLoudSpeaker: Bool {
        get {
            return PhoneSettings.defaultLoudSpeaker
        }
        set {
            PhoneSettings.defaultLoudSpeaker = newValue
        }
    }

    private let authenticationStrategy: AuthenticationStrategy
    private let applicationLifecycleObserver: ApplicationLifecycleObserver
    private let webSocketService: WebSocketService
    private let callManager: CallManager
    private let deviceService: DeviceService
    
    init(authenticationStrategy: AuthenticationStrategy, applicationLifecycleObserver: ApplicationLifecycleObserver, webSocketService: WebSocketService, callManager: CallManager, deviceService: DeviceService) {
        self.authenticationStrategy = authenticationStrategy
        self.applicationLifecycleObserver = applicationLifecycleObserver
        self.webSocketService = webSocketService
        self.callManager = callManager
        self.deviceService = deviceService
        webSocketService.deviceReregistrationStrategy = self
    }
    
    /// Registers the user’s device to Spark. Subsequent invocations of this method should perform a device refresh.
    ///
    /// - parameter completionHandler: A closure to be executed once the registration is completed. True means success, and False means failure.
    /// - returns: Void
    /// - note: This function is expected to run on main thread.
    public func register(_ completionHandler: ((Bool) -> Void)?) {
        // XXX This guard means that the completion handler may never be fired
        guard authenticationStrategy.authorized else {
            Logger.error("Skip registering device due to no authorization")
            return
        }
        
        deviceService.registerDevice() { deviceRegistrationInformation in
            if let deviceRegistrationInformation = deviceRegistrationInformation {
                self.applicationLifecycleObserver.startObserving()
                self.callManager.fetchActiveCalls()
                self.webSocketService.connect(deviceRegistrationInformation.webSocketUrl)
            }
            completionHandler?(deviceRegistrationInformation != nil)
        }
    }
    
    /// Removes the user’s device from Spark and disconnects the websocket. 
    /// Subsequent invocations of this method should behave as a no-op.
    ///
    /// - parameter completionHandler: A closure to be executed once the action is completed. True means success, and False means failure.
    /// - returns: Void
    /// - note: This function is expected to run on main thread.
    public func deregister(_ completionHandler: ((Bool) -> Void)?) {
        callManager.clearReachabilityState()
        applicationLifecycleObserver.stopObserving()
        webSocketService.disconnect()
        deviceService.deregisterDevice() { success in
            completionHandler?(success)
        }
    }
    
    /// Makes a call to intended recipient.
    ///
    /// - parameter address: Intended recipient address. Supported URIs: Spark URI (e.g. spark:shenning@cisco.com), SIP / SIPS URI (e.g. sip:1234@care.acme.com), Tropo URI (e.g. tropo:999123456). Supported shorthand: Email address (e.g. shenning@cisco.com), App username (e.g. jp)
    /// - parameter option: Media option for call: audio-only, audio+video etc. If it contains video, need to specify render view for video.
    /// - parameter completionHandler: A closure to be executed once the action is completed. True means success, and False means failure.
    /// - returns: Call object
    /// - note: This function is expected to run on main thread.
    public func dial(_ address: String, option: MediaOption, completionHandler: @escaping (Bool) -> Void) -> Call {
        let call = callManager.createOutgoingCall()
        call.dial(address: address, option: option) { success in
            completionHandler(success)
        }
        return call
    }
    
    /// Requests the end user approve the H.264 codec license from Cisco Systems.
    ///
    /// - returns: Void
    /// - note: Invoking the function is optional since the license activation alert will appear automatically during the first video call.
    public func requestVideoCodecActivation() {
        callManager.requestVideoCodecActivation()
    }
    
    /// Prevents the SDK from checking H.264 video codec license activation.
    ///
    /// - returns: Void
    /// - note: The function is expected to be called only by Cisco application. 3rd-party application should NOT call this API.
    public func disableVideoCodecActivation() {
        callManager.disableVideoCodecActivation()
    }
    
    /// Requests access for media (audio and video), user can change the settings in iOS device settings.
    ///
    /// - parameter type: Request access to different media types.
    /// - parameter completionHandler: A closure to be executed once the action is completed. True means access granted, and False means not.
    /// - returns: Void
    /// - note: This function is expected to run on main thread.
    public func requestMediaAccess(_ type: MediaAccessType, completionHandler: ((Bool) -> Void)?) {
        switch (type) {
        case .audio:
            requestMediaAccess(AVMediaTypeAudio) {
                completionHandler?($0)
            }
        case .video:
            requestMediaAccess(AVMediaTypeVideo) {
                completionHandler?($0)
            }
        case .audioVideo:
            requestMediaAccess(AVMediaTypeAudio) {
                if !$0 {
                    completionHandler?(false)
                } else {
                    self.requestMediaAccess(AVMediaTypeVideo) {
                        completionHandler?($0)
                    }
                }
            }
        }
    }
    
    private func requestMediaAccess(_ mediaType: String, completionHandler: ((Bool) -> Void)?) {
        AVCaptureDevice.requestAccess(forMediaType: mediaType) {
            let granted = $0
            DispatchQueue.main.async {
                completionHandler?(granted)
            }
        }
    }
}

extension Phone: DeviceReregistrationStrategy {
    func reregisterDevice() {
        register(nil)
    }
}
