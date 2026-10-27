import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

struct KitchenEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var profile: KitchenProfile
    @State private var calibration = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var calibrationReset = false
    var body: some View {
        Form {
            Section { TextField("주방 이름", text: $profile.name); TextField("화구 위치", text: $profile.burner) } header: { Text("주방 프로필") } footer: { Text("화구마다 가열기와 화력을 저장해주세요.") }
            Section("가열기") {
                Picker("가열원", selection: $profile.heatingType) { ForEach(HeatingType.allCases) { Text($0.rawValue).tag($0) } }
                Picker("조작 방식", selection: $profile.controlType) { ForEach(ControlType.allCases) { Text($0.rawValue).tag($0) } }
                DisclosureGroup("기기 사진 (선택)") {
                PhotosPicker(selection: $photo, matching: .images) { Label("가열기 사진 선택", systemImage: "photo") }
                Button { Task { let granted = await AVCaptureDevice.requestAccess(for: .video); if granted && UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { store.message = "카메라를 사용할 수 없습니다. 사진 선택 또는 직접 입력을 이용해주세요." } } } label: { Label("가열기 촬영", systemImage: "camera") }
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180); Button("사진 제거", role: .destructive) { self.image = nil } }
                Text("사진은 참고용으로만 표시합니다. 유형·화력은 직접 입력하고 확인해주세요. 사진으로 출력이나 온도를 확정하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if profile.controlType.isNumeric { NumericHeatEditor(profile: $profile) }
                else { DialHeatEditor(profile: $profile) }
            } header: { Text(profile.controlType.isNumeric ? "슬라이더로 화력 설정" : "다이얼 위치 설정") }
            Section { Text("물 \(profile.calibrationWater)ml를 \(profile.setting(.medium))에서 가열하고 끓기까지 걸린 시간을 기록해주세요. 앱은 가열기를 제어하지 않습니다.").font(.subheadline)
                if calibrationReset { Text("화력 설정이 바뀌었습니다. 보정 시간은 다시 측정해주세요.").font(.caption).foregroundStyle(Palette.orange) }
                TextField("끓기까지 걸린 초 (선택)", text: $calibration).keyboardType(.numberPad)
                Text("보정은 중불에서 측정한 참고값입니다. 다른 단계의 실제 출력·온도를 확정하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("선택 · 물 끓임 보정") }
            Section { PrimaryButton(title: "확인하고 주방 저장", icon: "checkmark") {
                if !calibration.isEmpty { guard let seconds = Int(calibration), (10...3600).contains(seconds) else { store.message = "보정 시간은 10~3600초로 입력해주세요."; return }; profile.calibrationSeconds = seconds; profile.calibrationSetting = profile.setting(.medium) } else { profile.calibrationSeconds = nil }
                if store.saveKitchen(profile) { dismiss() }
            }.listRowBackground(Color.clear) }
        }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle("주방 등록").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        .onAppear { calibration = profile.calibrationSeconds.map(String.init) ?? "" }
        .onChange(of: profile.heatingType) { _, type in if type == .gas { profile.controlType = .knob } }
        .onChange(of: profile.controlType) { _, type in
            if !type.isNumeric && profile.dialConfiguration == nil && !store.data.kitchens.contains(where: { $0.id == profile.id }) { profile.dialConfiguration = .clockwiseFromOff() }
        }
        .onChange(of: profile.numericMap) { _, _ in clearCalibration() }
        .onChange(of: profile.dialConfiguration) { _, _ in clearCalibration() }
        .onChange(of: profile.dialMap) { _, _ in clearCalibration() }
        .onChange(of: photo) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } } }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { image = $0 } }
    }
    private func clearCalibration() {
        if profile.calibrationSeconds != nil || !calibration.isEmpty { calibrationReset = true; calibration = ""; profile.calibrationSeconds = nil }
    }
}
