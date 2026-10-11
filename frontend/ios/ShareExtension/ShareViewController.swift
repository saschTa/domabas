import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let store = ShareSessionStore()
  private let client = ShareHTTPClient()
  private var snapshot: ShareSession?
  private var providers: [NSItemProvider] = []
  private var operation: Task<Void, Never>?
  private var receiver: ShareAttachmentReceiver?
  private var finished = false
  private var sending = false
  private let detail = UILabel()
  private let uploadButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("domabas-share-\(UUID().uuidString)")

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let title = UILabel()
    title.text = "Share with Domabas"
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true
    detail.numberOfLines = 0
    detail.font = .preferredFont(forTextStyle: .body)
    detail.adjustsFontForContentSizeCategory = true
    detail.text = "Checking your library…"
    uploadButton.setTitle("Upload", for: .normal)
    uploadButton.isEnabled = false
    uploadButton.addTarget(self, action: #selector(upload), for: .touchUpInside)
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    let buttons = UIStackView(arrangedSubviews: [cancelButton, spinner, uploadButton])
    buttons.distribution = .equalSpacing
    let stack = UIStackView(arrangedSubviews: [title, detail, buttons])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
    ])
    preferredContentSize = CGSize(width: 420, height: 400)
    isModalInPresentation = true
    providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    spinner.startAnimating()
    operation = Task { await prepare() }
  }

  @MainActor private func prepare() async {
    do {
      guard !providers.isEmpty, providers.count <= 20,
            providers.allSatisfy({ $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
        throw ShareUploadFailure.message("Share up to 20 PDF files or images at a time.")
      }
      let session = try store.session()
      let library = try await ShareUploadAPI(client: client).identity(session)
      try Task.checkCancellation()
      snapshot = session
      detail.text = "Upload \(providers.count) \(providers.count == 1 ? "file" : "files") to \(library)?\n\nServer: \(session.context.endpoint)\n\nKeep this sheet open until each upload finishes. PDFs, PNGs and JPEGs keep their original bytes. Other still images are converted to JPEG (up to 4096 pixels)."
      uploadButton.isEnabled = true
    } catch { show(error) }
    spinner.stopAnimating()
  }

  @objc private func upload() {
    guard let snapshot, !sending, !finished else { return }
    sending = true
    uploadButton.isEnabled = false
    spinner.startAnimating()
    operation = Task {
      var outcomes: [String] = []
      do {
        guard try store.session().context == snapshot.context else {
          throw ShareUploadFailure.message("Your library changed. Close this sheet and share again.")
        }
        _ = try await ShareUploadAPI(client: client).identity(snapshot)
        for old in (try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
          if old.lastPathComponent.hasPrefix("domabas-share-"),
             let date = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
             date.timeIntervalSinceNow < -86400 { try? FileManager.default.removeItem(at: old) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.complete])
        for (index, provider) in providers.enumerated() {
          try Task.checkCancellation()
          guard try store.session().context == snapshot.context else {
            throw ShareUploadFailure.message("Your session changed. Remaining files were not sent.")
          }
          detail.text = (outcomes + ["Preparing file \(index + 1) of \(providers.count)…"]).joined(separator: "\n\n")
          let folder = directory.appendingPathComponent(String(index))
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          do {
            let receiver = ShareAttachmentReceiver()
            self.receiver = receiver
            let received = try await receiver.receive(provider, in: folder)
            self.receiver = nil
            let name = provider.suggestedName ?? received.name
            let boundary = "domabas-\(UUID().uuidString)"
            let (file, body) = try await Task.detached {
              let file = try ShareUploadFile.prepare(received.url, name: name, directory: folder)
              return (file, try file.multipart(in: folder, boundary: boundary))
            }.value
            try Task.checkCancellation()
            guard try store.session().context == snapshot.context else {
              throw ShareUploadFailure.message("Your session changed. This file was not sent.")
            }
            detail.text = (outcomes + ["Uploading \(file.filename)…"]).joined(separator: "\n\n")
            let outcome = await ShareUploadAPI(client: client).upload(file, body: body, boundary: boundary, session: snapshot)
            outcomes.append("\(file.filename): \(outcome)")
            if outcome.hasPrefix("Outcome unknown") || outcome.hasPrefix("Not uploaded: sign in") { break }
          } catch is CancellationError { throw CancellationError() }
          catch { outcomes.append("File \(index + 1): \(message(error))") }
          try? FileManager.default.removeItem(at: folder)
        }
        try Task.checkCancellation()
        if outcomes.count < providers.count { outcomes.append("Remaining files were not sent.") }
        detail.text = outcomes.joined(separator: "\n\n")
      } catch {
        if !finished { detail.text = (outcomes + [message(error)]).joined(separator: "\n\n") }
      }
      spinner.stopAnimating()
      sending = false
      cancelButton.setTitle("Done", for: .normal)
      try? FileManager.default.removeItem(at: directory)
    }
  }

  @objc private func cancel() {
    if sending {
      let alert = UIAlertController(title: "Stop uploading?", message: "A file already sent may have been accepted. Check the library before sharing it again.", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Keep uploading", style: .cancel))
      alert.addAction(UIAlertAction(title: "Stop", style: .destructive) { [weak self] _ in self?.finish() })
      present(alert, animated: true)
    } else { finish() }
  }

  private func finish() {
    finished = true
    operation?.cancel()
    receiver?.cancel()
    client.close()
    try? FileManager.default.removeItem(at: directory)
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func message(_ error: Error) -> String {
    (error as? ShareUploadFailure)?.message ?? "Unable to connect or read the shared file. Open Domabas to check your server, then share again."
  }
  private func show(_ error: Error) {
    if !finished { detail.text = message(error) }
  }
}
