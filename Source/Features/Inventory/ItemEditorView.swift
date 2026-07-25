import PhotosUI
import SwiftUI
import UIKit

struct ItemEditorView: View {
    @EnvironmentObject private var store: GroceryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContentLanguage) private var catalogLanguage

    @State private var draft: GroceryItem
    @State private var nameForEditing: String = ""
    @State private var didApplyInitialDisplayName = false
    @State private var isDeleteConfirmationPresented = false

    @State private var pendingImage: UIImage?
    @State private var removeImageOnSave = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false

    init(item: GroceryItem) {
        _draft = State(initialValue: item)
    }

    private var isValid: Bool {
        !nameForEditing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedPhoto: UIImage? {
        if removeImageOnSave { return nil }
        if let pendingImage { return pendingImage }
        if draft.hasDisplayablePhoto { return ItemImageStore.loadImage(forItemID: draft.id) }
        return nil
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        Form {
            Section {
                TextField(LocalizedCopy.nameField, text: $nameForEditing)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(catalogLanguage == .hebrew ? .trailing : .leading)
            }

            Section {
                CatalogItemSectionPicker(
                    label: LocalizedCopy.homeSectionLabel,
                    kind: .inventory,
                    selection: $draft.inventoryTagID
                )

                CatalogItemSectionPicker(
                    label: LocalizedCopy.storeSectionLabel,
                    kind: .shopping,
                    selection: $draft.shoppingTagID
                )
            } header: {
                Text(LocalizedCopy.sectionsHeader)
            } footer: {
                Text(LocalizedCopy.itemSectionsFormFooter)
            }

            Section(LocalizedCopy.photo) {
                if let ui = displayedPhoto {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                }

                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label(LocalizedCopy.chooseFromLibrary, systemImage: "photo.on.rectangle.angled")
                }

                if cameraAvailable {
                    Button {
                        isCameraPresented = true
                    } label: {
                        Label(LocalizedCopy.takePhoto, systemImage: "camera")
                    }
                }

                if displayedPhoto != nil {
                    Button(role: .destructive) {
                        pendingImage = nil
                        removeImageOnSave = true
                    } label: {
                        Label(LocalizedCopy.removePhoto, systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Text(LocalizedCopy.deleteItem)
                }
            }
        }
        .navigationTitle(LocalizedCopy.editItem)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LocalizedCopy.cancel) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedCopy.save) {
                    applySave()
                }
                .fontWeight(.bold)
                .appThemeTint()
                .disabled(!isValid)
            }
        }
        .onAppear {
            guard !didApplyInitialDisplayName else { return }
            didApplyInitialDisplayName = true
            nameForEditing = draft.displayName(appContentLanguage: catalogLanguage)
        }
        .onChange(of: catalogLanguage) { _, _ in
            if let current = store.item(for: draft.id) {
                draft = current
                nameForEditing = current.name
                pendingImage = nil
                removeImageOnSave = false
            } else {
                dismiss()
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data)
                {
                    await MainActor.run {
                        pendingImage = ui
                        removeImageOnSave = false
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker(isPresented: $isCameraPresented) { img in
                pendingImage = img
                removeImageOnSave = false
            }
            .ignoresSafeArea()
        }
        .alert(
            LocalizedCopy.deleteThisItemAlertTitle,
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(LocalizedCopy.cancel, role: .cancel) {
                isDeleteConfirmationPresented = false
            }
            Button(LocalizedCopy.delete, role: .destructive) {
                withAnimation(.snappy) {
                    store.deleteCatalogItem(draft.id)
                }
                dismiss()
            }
        } message: {
            Text(LocalizedCopy.deleteItemMessage(itemName: draft.displayName(appContentLanguage: catalogLanguage)))
        }
    }

    private func applySave() {
        var updated = draft
        updated.name = CatalogContentLocalization.storedItemName(
            fromDisplay: nameForEditing,
            language: catalogLanguage
        )
        if removeImageOnSave {
            ItemImageStore.delete(forItemID: draft.id)
            updated.hasImage = false
        } else if let img = pendingImage {
            try? ItemImageStore.save(img, forItemID: draft.id)
            updated.hasImage = ItemImageStore.fileExists(forItemID: draft.id)
        }
        store.updateCatalogItem(updated)
        dismiss()
    }
}
