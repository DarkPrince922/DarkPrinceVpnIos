import SwiftUI

struct LoginView: View {

    enum Mode {
        /// Обычный вход при первом запуске.
        case initial
        /// Гость заводит собственный аккаунт, не теряя чужую подписку.
        case upgrade
    }

    let mode: Mode
    var onClose: (() -> Void)?

    @EnvironmentObject private var session: SessionModel
    @Environment(\.openURL) private var openURL

    @State private var tab = 0
    @State private var email = ""
    @State private var password = ""
    @State private var referralCode = ""
    @State private var registerMode = false

    @State private var loading = false
    @State private var waitingTelegram = false
    @State private var error: String?
    @State private var info: String?
    @State private var telegramTask: Task<Void, Never>?

    @State private var showScanner = false
    @State private var showImagePicker = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header

                    Picker("", selection: $tab) {
                        Text("Telegram").tag(0)
                        Text("Почта").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if tab == 0 { telegramBlock } else { emailBlock }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let info {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(Theme.goldSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider().overlay(Color.white.opacity(0.1))

                    if mode == .upgrade {
                        // подписка по QR у гостя уже есть — здесь нужен только аккаунт
                        Button("Вернуться") { onClose?() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    } else {
                        qrBlock
                    }
                }
                .padding(24)
            }
        }
        .onDisappear { telegramTask?.cancel() }
        .sheet(isPresented: $showScanner) {
            QrScannerView { code in
                showScanner = false
                if let code { activateShared(code) }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            QrImagePicker { code in
                showImagePicker = false
                guard let code else {
                    error = "QR-код на картинке не распознан. Попробуйте изображение " +
                        "покрупнее или отсканируйте код камерой."
                    return
                }
                activateShared(code)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 72))
                .foregroundStyle(Theme.gold)
                .padding(.top, 24)

            Text(mode == .upgrade ? "Свой аккаунт" : "Вход")
                .font(.largeTitle.bold())

            if mode == .upgrade {
                Text(
                    "Зарегистрируйтесь или войдите, чтобы купить собственную подписку. " +
                    "Доступ, которым с вами поделились, продолжит работать, пока не " +
                    "заработает ваша."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var telegramBlock: some View {
        VStack(spacing: 12) {
            if waitingTelegram {
                ProgressView()
                Text("Откройте Telegram и нажмите «Start», ждём подтверждения…")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Отмена") {
                    telegramTask?.cancel()
                    waitingTelegram = false
                }
                .buttonStyle(.bordered)
            } else {
                Button("Войти через Telegram") { startTelegramAuth() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(loading)

                Text(
                    "Подойдёт, если вы уже пользовались нашим ботом: подписка и баланс " +
                    "подтянутся автоматически."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emailBlock: some View {
        VStack(spacing: 12) {
            TextField("E-mail", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Пароль", text: $password)
                .textContentType(registerMode ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if registerMode {
                TextField("Реферальный код (необязательно)", text: $referralCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            Button(registerMode ? "Зарегистрироваться" : "Войти") { submitEmail() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(loading || !email.contains("@") || password.count < 6)

            Button(registerMode ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Зарегистрируйтесь") {
                registerMode.toggle()
            }
            .font(.footnote)

            if !registerMode {
                Button("Забыли пароль?") {
                    guard email.contains("@") else { return }
                    Task {
                        await AuthRepository.shared.forgotPassword(email: email)
                        info = "Если такой e-mail зарегистрирован, мы отправили письмо для сброса пароля."
                    }
                }
                .font(.footnote)
            }
        }
    }

    private var qrBlock: some View {
        VStack(spacing: 12) {
            Button("Сканировать QR камерой") { showScanner = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            Button("Загрузить QR из галереи") { showImagePicker = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            Text(
                "Если вам дали доступ к подписке — отсканируйте QR владельца или " +
                "выберите присланную картинку."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Действия

    private func startTelegramAuth() {
        error = nil
        info = nil
        loading = true
        telegramTask?.cancel()
        telegramTask = Task {
            await AuthRepository.shared.telegramDeepLinkAuth { event in
                Task { @MainActor in
                    switch event {
                    case .openTelegram(let telegram, let web):
                        loading = false
                        waitingTelegram = true
                        // если Telegram не установлен, уводим в браузер
                        openURL(telegram) { opened in
                            if !opened { openURL(web) }
                        }
                    case .waiting:
                        break
                    case .success:
                        loading = false
                        waitingTelegram = false
                        session.didLogIn()
                        onClose?()
                    case .failed(let message):
                        loading = false
                        waitingTelegram = false
                        error = message
                    }
                }
            }
        }
    }

    private func submitEmail() {
        error = nil
        info = nil
        loading = true
        Task {
            if registerMode {
                let result = await AuthRepository.shared.emailRegister(
                    email: email,
                    password: password,
                    referralCode: referralCode.isEmpty ? nil : referralCode
                )
                loading = false
                if result.success, SharedStore.shared.isLoggedIn {
                    session.didLogIn()
                    onClose?()
                } else if result.success {
                    info = result.message
                } else {
                    error = result.message
                }
            } else {
                let failure = await AuthRepository.shared.emailLogin(email: email, password: password)
                loading = false
                if failure == nil {
                    session.didLogIn()
                    onClose?()
                } else {
                    error = failure
                }
            }
        }
    }

    private func activateShared(_ code: String) {
        error = nil
        loading = true
        Task {
            let failure = await SubscriptionRepository.shared.activateGuestSubscription(code)
            loading = false
            if let failure {
                error = failure
            } else {
                session.didActivateGuestSubscription()
                onClose?()
            }
        }
    }
}
