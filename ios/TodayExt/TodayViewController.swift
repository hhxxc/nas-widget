import UIKit
import NotificationCenter

/// 负一屏「可写」老式 Today 小组件。
/// iOS 15 的桌面 WidgetKit 小组件是只读快照，但 Today 扩展是真 ViewController，
/// 可以放输入框/按钮，直接在负一屏新建和勾选待办（iOS 17 前唯一可交互形态）。
final class TodayViewController: UIViewController, NCWidgetProviding, UITextFieldDelegate {

    private let titleLabel = UILabel()
    private let field = UITextField()
    private let addButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let listStack = UIStackView()
    private let openButton = UIButton(type: .system)

    private var items: [TodoItem] = []
    private var busy = false

    private var accent: UIColor { UIColor(red: 0.925, green: 0.322, blue: 0.263, alpha: 1) }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        extensionContext?.widgetLargestAvailableDisplayMode = .expanded
        buildUI()
        items = SettingsStore.shared.cachedTodos()
        render()
        refresh()
    }

    // MARK: - NCWidgetProviding

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        preferredContentSize = activeDisplayMode == .expanded
            ? CGSize(width: 0, height: 280)
            : maxSize
    }

    func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
        let before = items
        refresh { [weak self] in
            guard let self = self else { completionHandler(.noData); return }
            completionHandler(before == self.items ? .noData : .newData)
        }
    }

    // MARK: - UI

    private func buildUI() {
        titleLabel.text = "待办事项"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = UIColor(white: 0.1, alpha: 1)

        field.placeholder = "记点什么，回车/点添加"
        field.borderStyle = .none
        field.backgroundColor = UIColor(white: 0.96, alpha: 1)
        field.layer.cornerRadius = 9
        field.font = .systemFont(ofSize: 15)
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.returnKeyType = .done
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 38).isActive = true

        addButton.setTitle("添加", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        addButton.backgroundColor = accent
        addButton.layer.cornerRadius = 9
        addButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        addButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        let inputRow = UIStackView(arrangedSubviews: [field, addButton])
        inputRow.spacing = 8

        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 0.55, alpha: 1)
        hintLabel.text = "暂无待办事项"
        hintLabel.isHidden = true

        listStack.axis = .vertical
        listStack.spacing = 6

        openButton.setTitle("在 App 中查看", for: .normal)
        openButton.setTitleColor(accent, for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 12)
        openButton.contentHorizontalAlignment = .left
        openButton.addTarget(self, action: #selector(openApp), for: .touchUpInside)

        let root = UIStackView(arrangedSubviews: [titleLabel, inputRow, hintLabel, listStack, openButton])
        root.axis = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func render() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let undone = items.filter { !$0.done }
        hintLabel.isHidden = !undone.isEmpty
        listStack.isHidden = undone.isEmpty
        for item in undone.prefix(6) {
            listStack.addArrangedSubview(row(for: item))
        }
    }

    private func row(for item: TodoItem) -> UIView {
        let check = UIButton(type: .system)
        check.layer.cornerRadius = 7
        check.layer.borderWidth = 1.3
        check.layer.borderColor = UIColor(white: 0.8, alpha: 1).cgColor
        check.widthAnchor.constraint(equalToConstant: 22).isActive = true
        check.heightAnchor.constraint(equalToConstant: 22).isActive = true
        check.addAction(UIAction { [weak self] _ in self?.toggle(item) }, for: .touchUpInside)

        let label = UILabel()
        label.text = item.content
        label.font = .systemFont(ofSize: 14)
        label.textColor = UIColor(white: 0.12, alpha: 1)
        label.numberOfLines = 1

        let row = UIStackView(arrangedSubviews: [check, label])
        row.spacing = 8
        row.alignment = .center
        return row
    }

    // MARK: - Actions

    @objc private func addTapped() {
        submit()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }

    private func submit() {
        let content = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !busy else { return }
        busy = true
        addButton.isEnabled = false
        Task { @MainActor in
            do {
                let item = try await APIClient.addTodo(content: content)
                field.text = ""
                items.insert(item, at: 0)
                render()
            } catch {
                hintLabel.text = "添加失败：\(error.localizedDescription)"
                hintLabel.isHidden = false
            }
            busy = false
            addButton.isEnabled = true
        }
    }

    private func toggle(_ item: TodoItem) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            do {
                try await APIClient.setDone(id: item.id, done: true)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].done = true
                }
                render()
            } catch {
                hintLabel.text = "更新失败：\(error.localizedDescription)"
                hintLabel.isHidden = false
            }
            busy = false
        }
    }

    @objc private func openApp() {
        if let url = URL(string: "naswidget://add") {
            extensionContext?.open(url, completionHandler: nil)
        }
    }

    // MARK: - Data

    private func refresh(completion: (() -> Void)? = nil) {
        let store = SettingsStore.shared
        guard store.isConfigured, store.isAuthenticated || store.hasCredentials else {
            hintLabel.text = "请在 App 内登录后使用"
            hintLabel.isHidden = false
            listStack.isHidden = true
            completion?()
            return
        }
        Task { @MainActor in
            do {
                items = try await APIClient.fetchTodos()
            } catch {
                items = store.cachedTodos()
            }
            render()
            completion?()
        }
    }
}
