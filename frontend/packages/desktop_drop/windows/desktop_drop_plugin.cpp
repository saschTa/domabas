// Modified by Domabas contributors from desktop_drop 0.8.4; see ../CHANGES.md.

#include "include/desktop_drop/desktop_drop_plugin.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <algorithm>
#include <vector>
#include <limits>
#include <shellapi.h>

namespace {

    using FlutterMethodChannel = std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>;


    using namespace std::literals::string_literals;

    std::string ws2s(const std::wstring &value) {
        if (value.empty() || value.length() > 32767) return {};
        const int length = static_cast<int>(value.length());
        const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), length, nullptr, 0, nullptr, nullptr);
        if (bytes <= 0) return {};
        std::string result(static_cast<size_t>(bytes), '\0');
        const int copied = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), length, result.data(), bytes, nullptr, nullptr);
        return copied == bytes ? result : std::string{};
    }

    class DesktopDropTarget : public IDropTarget {
    public:

        DesktopDropTarget(FlutterMethodChannel channel, HWND window_handle);

        HRESULT DragEnter(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;

        HRESULT DragOver(DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;

        HRESULT DragLeave() override;

        HRESULT Drop(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;

        HRESULT QueryInterface(const IID &riid, void **ppvObject) override;

        ULONG AddRef() override;

        ULONG Release() override;

        virtual ~DesktopDropTarget();

    private:
        FlutterMethodChannel channel_;
        HWND window_handle_;
        LONG ref_count_;
        bool need_revoke_ole_initialize_;
        bool accepts_files_ = false;
    };

    class DesktopDropPlugin : public flutter::Plugin {

    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        explicit DesktopDropPlugin(DesktopDropTarget *target);

        ~DesktopDropPlugin() override;

    private:

        DesktopDropTarget *target_;

    };

    DesktopDropPlugin::DesktopDropPlugin(DesktopDropTarget *target) : target_(target) {
        target_->AddRef();
    }

    DesktopDropPlugin::~DesktopDropPlugin() {
        target_->Release();
    }


    // static
    void DesktopDropPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarWindows *registrar) {
        auto channel =
                std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                        registrar->messenger(), "desktop_drop",
                        &flutter::StandardMethodCodec::GetInstance());

        HWND hwnd = nullptr;
        if (registrar->GetView()) {
            hwnd = registrar->GetView()->GetNativeWindow();
        }

        if (hwnd == nullptr) {
            // no window, no drop.
            return;
        }

        channel->SetMethodCallHandler([](const auto &call, auto result) {
            result->NotImplemented();
        });

        auto drop_target = new DesktopDropTarget(std::move(channel), hwnd);

        auto plugin = std::make_unique<DesktopDropPlugin>(drop_target);

        registrar->AddPlugin(std::move(plugin));
    }


    DesktopDropTarget::DesktopDropTarget(FlutterMethodChannel channel, HWND window_handle) : channel_(
            std::move(channel)), window_handle_(window_handle), ref_count_(0), need_revoke_ole_initialize_(false) {
        auto ret = RegisterDragDrop(window_handle_, this);
        if (ret == E_OUTOFMEMORY) {
            OleInitialize(nullptr);
            ret = RegisterDragDrop(window_handle_, this);
            if (ret == 0) {
                need_revoke_ole_initialize_ = true;
            }
        }

        if (ret != 0) {
            std::cout << "RegisterDragDrop failed: " << ret << std::endl;
        }
    }

    HRESULT DesktopDropTarget::DragEnter(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {
        FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
        accepts_files_ = pDataObj != nullptr && pDataObj->QueryGetData(&format) == S_OK;
        *pdwEffect = accepts_files_ && (*pdwEffect & DROPEFFECT_COPY) ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        if (*pdwEffect == DROPEFFECT_NONE) {
            channel_->InvokeMethod("exited", std::make_unique<flutter::EncodableValue>());
            return S_OK;
        }
        POINT point = {pt.x, pt.y};
        ScreenToClient(window_handle_, &point);
        channel_->InvokeMethod("entered", std::make_unique<flutter::EncodableValue>(
                flutter::EncodableList{
                        flutter::EncodableValue(double(point.x)),
                        flutter::EncodableValue(double(point.y))
                }
        ));
        return 0;
    }

    HRESULT DesktopDropTarget::DragOver(DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {
        *pdwEffect = accepts_files_ && (*pdwEffect & DROPEFFECT_COPY) ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        if (*pdwEffect == DROPEFFECT_NONE) {
            channel_->InvokeMethod("exited", std::make_unique<flutter::EncodableValue>());
            return S_OK;
        }
        POINT point = {pt.x, pt.y};
        ScreenToClient(window_handle_, &point);
        channel_->InvokeMethod("updated", std::make_unique<flutter::EncodableValue>(
                flutter::EncodableList{
                        flutter::EncodableValue(double(point.x)),
                        flutter::EncodableValue(double(point.y))
                }
        ));
        return 0;
    }

    HRESULT DesktopDropTarget::DragLeave() {
        accepts_files_ = false;
        channel_->InvokeMethod("exited", std::make_unique<flutter::EncodableValue>());
        return 0;
    }

    HRESULT DesktopDropTarget::Drop(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {
        *pdwEffect = accepts_files_ && (*pdwEffect & DROPEFFECT_COPY) ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        accepts_files_ = false;
        if (*pdwEffect == DROPEFFECT_NONE || pDataObj == nullptr) {
            channel_->InvokeMethod("exited", std::make_unique<flutter::EncodableValue>());
            return S_OK;
        }
        flutter::EncodableList list;
        FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
        STGMEDIUM medium = {};
        if (pDataObj->GetData(&format, &medium) == S_OK) {
            struct MediumRelease {
                STGMEDIUM *value;
                ~MediumRelease() { ReleaseStgMedium(value); }
            } release{&medium};
            if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal != nullptr) {
                HDROP drop = reinterpret_cast<HDROP>(medium.hGlobal);
                const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
                if (count > 20) {
                    channel_->InvokeMethod("rejected", std::make_unique<flutter::EncodableValue>("Choose up to 20 files. None of this batch were uploaded."));
                    return S_OK;
                }
                for (UINT i = 0; i < count; ++i) {
                    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
                    if (length == 0 || length >= 32768) {
                        list.push_back(flutter::EncodableValue(""));
                        continue;
                    }
                    std::vector<wchar_t> filename(static_cast<size_t>(length) + 1, L'\0');
                    const UINT copied = DragQueryFileW(drop, i, filename.data(), length + 1);
                    if (copied != length || filename[length] != L'\0') {
                        list.push_back(flutter::EncodableValue(""));
                        continue;
                    }
                    list.push_back(flutter::EncodableValue(ws2s(std::wstring(filename.data(), length))));
                }
            }
        }
        channel_->InvokeMethod("performOperation", std::make_unique<flutter::EncodableValue>(list));
        return S_OK;
    }

    HRESULT DesktopDropTarget::QueryInterface(const IID &iid, void **ppvObject) {
        if (iid == IID_IDropTarget || iid == IID_IUnknown) {
            AddRef();
            *ppvObject = this;
            return S_OK;
        } else {
            *ppvObject = nullptr;
            return E_NOINTERFACE;
        }
    }

    ULONG DesktopDropTarget::AddRef() {
        return InterlockedIncrement(&ref_count_);
    }

    ULONG DesktopDropTarget::Release() {
        LONG count = InterlockedDecrement(&ref_count_);

        if (count == 0) {
            delete this;
            return 0;
        } else {
            return count;
        }
    }

    DesktopDropTarget::~DesktopDropTarget() {
        RevokeDragDrop(window_handle_);
        if (need_revoke_ole_initialize_) {
            OleUninitialize();
        }
    }

}  // namespace

void DesktopDropPluginRegisterWithRegistrar(
        FlutterDesktopPluginRegistrarRef registrar) {
    DesktopDropPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarManager::GetInstance()
                    ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));

}
