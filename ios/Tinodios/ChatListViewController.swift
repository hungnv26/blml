//
//  ChatListViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

protocol ChatListDisplayLogic: AnyObject {
    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?)
    func displayLoginView()
    func updateChat(_ name: String)
    func deleteChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    private static let kFooterHeight: CGFloat = 30

    @IBOutlet var chatListTableView: UITableView!

    var interactor: ChatListBusinessLogic?
    // What the table shows: allTopics with the search filter applied.
    var topics: [DefaultComTopic] = []
    // Everything the presenter delivered, unfiltered. Kept separate so
    // clearing the search restores the full list without a server round-trip.
    private var allTopics: [DefaultComTopic] = []
    private let searchField = UISearchTextField()
    var archivedTopics: [DefaultComTopic]?
    var numArchivedTopics: Int { return archivedTopics?.count ?? 0 }

    // Index of contacts: name => position in topics
    var rowIndex: [String: Int] = [:]
    var router: ChatListRoutingLogic?
    // Archived chats footer
    var archivedChatsFooter: UIView?

    private func setup() {
        let viewController = self
        let interactor = ChatListInteractor()
        let presenter = ChatListPresenter()
        let router = ChatListRouter()

        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController

        self.chatListTableView.register(UINib(nibName: "ChatListViewCell", bundle: nil), forCellReuseIdentifier: "ChatListViewCell")

        // Footer for Archived Chats link.
        archivedChatsFooter = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: ChatListViewController.kFooterHeight))
        archivedChatsFooter!.backgroundColor = tableView.backgroundColor
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: ChatListViewController.kFooterHeight))
        button.setTitle(NSLocalizedString("Archived Chats", comment: "View title"), for: .normal)
        button.setTitleColor(UIColor.darkGray, for: .normal)
        button.titleLabel?.font = button.titleLabel?.font.withSize(15)
        button.addTarget(self, action: #selector(navigateToArchive), for: .touchUpInside)
        archivedChatsFooter!.addSubview(button)
        tableView.tableFooterView = archivedChatsFooter
        // WhatsApp-style: the list is titled "Chats"; the brand lives on the
        // app icon and login screen, not the navigation bar.
        // navigationItem.title, not self.title: the storyboard sets an explicit
        // navigationItem title which would otherwise win.
        self.navigationItem.title = NSLocalizedString("Chats", comment: "Chat list title")
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    private func toggleFooter(visible: Bool) {
        let count = numArchivedTopics > 9 ? "9+" : String(numArchivedTopics)
        let button = tableView.tableFooterView!.subviews[0] as! UIButton
        button.setTitle(String(format: NSLocalizedString("Archived Chats (%@)", comment: "Button to open chat archive"), count), for: .normal)
        archivedChatsFooter!.isHidden = !visible
        tableView.tableFooterView = archivedChatsFooter
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setup()

        // Tone the large title down a step: the default ~34pt reads louder than
        // anything else on screen. 28pt keeps the hierarchy title > search > list.
        navigationController?.navigationBar.largeTitleTextAttributes =
            [.font: UIFont.systemFont(ofSize: 28, weight: .bold)]

        // WhatsApp-style search box under the "Chats" title. A slim
        // UISearchTextField in the table header rather than a UISearchController:
        // the system bar's height cannot be reduced, and it dwarfed the rows it
        // was meant to search.
        let headerHeight: CGFloat = 46
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: headerHeight))
        header.autoresizingMask = [.flexibleWidth]
        searchField.placeholder = NSLocalizedString("Search", comment: "Chat list search placeholder")
        searchField.font = .systemFont(ofSize: 15)
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .done
        searchField.autocorrectionType = .no
        searchField.frame = CGRect(x: 14, y: 4, width: header.bounds.width - 28, height: 36)
        searchField.autoresizingMask = [.flexibleWidth]
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchField.addTarget(self, action: #selector(dismissSearchKeyboard), for: .editingDidEndOnExit)
        header.addSubview(searchField)
        tableView.tableHeaderView = header

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appGoingInactive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    @objc
    func appBecameActive() {
        self.interactor?.setup()
        self.interactor?.attachToMeTopic()
        // Reload topics after the app became active.
        self.interactor?.loadAndPresentTopics()
    }
    @objc
    func appGoingInactive() {
        self.interactor?.cleanup()
        self.interactor?.leaveMeTopic()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.interactor?.setup()
        self.interactor?.attachToMeTopic()
        self.interactor?.loadAndPresentTopics()
    }

    // Continue listening on meTopic even when the VC isn't visible.
    // TODO: remote this.
    // override func viewDidDisappear(_ animated: Bool) {
    //     self.interactor?.cleanup()
    // }

    func displayLoginView() {
        UiUtils.logoutAndRouteToLoginVC()
    }

    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?) {
        assert(Thread.isMainThread)
        self.allTopics = topics
        self.archivedTopics = archivedTopics
        self.applySearchFilter()
        self.toggleFooter(visible: self.numArchivedTopics > 0)
    }

    @objc private func searchTextChanged() {
        applySearchFilter()
    }

    @objc private func dismissSearchKeyboard() {
        searchField.resignFirstResponder()
    }

    /// Rebuilds the visible list from `allTopics` and the current query.
    /// Matches the chat title and the About line, same fields Android's chat
    /// list filter uses. rowIndex must be rebuilt in the same pass: updateChat
    /// and deleteChat address rows through it, so a stale index would repaint
    /// or remove the wrong row while a filter is active.
    private func applySearchFilter() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            self.topics = allTopics
        } else {
            self.topics = allTopics.filter { topic in
                let hayStack = [topic.pub?.fn, topic.pub?.note, topic.comment]
                return hayStack.contains { $0?.lowercased().contains(query) ?? false }
            }
        }
        self.rowIndex = Dictionary(uniqueKeysWithValues: self.topics.enumerated().map { (index, topic) in (topic.name, index) })
        self.tableView!.reloadData()
    }

    func updateChat(_ name: String) {
        assert(Thread.isMainThread)
        guard let position = rowIndex[name] else { return }
        self.tableView!.reloadRows(at: [IndexPath(item: position, section: 0)], with: .none)
        self.toggleFooter(visible: self.numArchivedTopics > 0)
    }

    func deleteChat(_ name: String) {
        assert(Thread.isMainThread)
        // Drop from the unfiltered list too, or the chat would reappear the
        // moment the search box is cleared.
        self.allTopics.removeAll { $0.name == name }
        guard let position = rowIndex[name] else { return }
        self.topics.remove(at: position)
        self.rowIndex = Dictionary(uniqueKeysWithValues: self.topics.enumerated().map { (index, topic) in (topic.name, index) })
        self.tableView!.deleteRows(at: [IndexPath(item: position, section: 0)], with: .fade)
        self.toggleFooter(visible: self.numArchivedTopics > 0)
    }

    @objc private func navigateToArchive() {
        self.performSegue(withIdentifier: "Chats2Archive", sender: nil)
    }
}

// UITableViewController
extension ChatListViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Chats2Messages", let topicName = sender as? String {
            router?.routeToChat(withName: topicName, for: segue)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        toggleNoChatsNote(on: topics.isEmpty)
        return topics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatListViewCell") as! ChatListViewCell
        let topic = self.topics[indexPath.row]
        cell.fillFromTopic(topic: topic)
        return cell
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Delete item at indexPath
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "Swipe action"), handler: { _,_,_ in
            let topic = self.topics[indexPath.row]
            self.interactor?.deleteTopic(topic.name)
        })
        let archive = UIContextualAction(style: .normal, title: NSLocalizedString("Archive", comment: "Swipe action"), handler: { _,_,_ in
            let topic = self.topics[indexPath.row]
            self.interactor?.changeArchivedStatus(
                forTopic: topic.name, archived: !topic.isArchived)
        })

        return UISwipeActionsConfiguration(actions: [delete, archive])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.performSegue(withIdentifier: "Chats2Messages", sender: self.topics[indexPath.row].name)
    }
}

extension ChatListViewController {

    /// Show notification that the chat list is empty
    public func toggleNoChatsNote(on show: Bool) {
        if show {
            let rect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
            let messageLabel = UILabel(frame: rect)
            messageLabel.text = NSLocalizedString("You have no chats\n\n¯\\_(ツ)_/¯", comment: "Placeholder when no chats found")
            messageLabel.textColor = .darkGray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            tableView.backgroundView = messageLabel
        } else {
            tableView.backgroundView = nil
        }
    }
}
