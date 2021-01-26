//
//  ScheduledNotificationsViewController.swift
//  Nice Photon
//
//  Created by Oleg Dreyman on 1/26/21.
//

import NiceUI
import UserNotifications

public final class ScheduledNotificationsViewController: UIViewController {
    
    enum Mode {
        case pending
        case delivered
    }
    
    let mode: Mode
    
    private init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    public init() {
        self.mode = .pending
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        self.mode = .pending
        super.init(coder: coder)
    }
    
    static let formatter: DateFormatter = {
        let form = DateFormatter()
        form.locale = Locale(identifier: "en_US_POSIX")
        form.setLocalizedDateFormatFromTemplate("MMddyyyyHHmmss")
        return form
    }()
    
    fileprivate var requests: [NotificationToShow] = []
    
    let tableView = StaticTableView()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        title = {
            switch mode {
            case .pending:
                return "Pending"
            case .delivered:
                return "Delivered"
            }
        }()
        
        addKeyboardAwareTableView(tableView)
        tableView.separatorStyle = .singleLine
        tableView.contentInset.top += 8
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.addDynamicSegment(provider: self, dataSet: \.requests, style: .default) { (cell) in
            let titleLabel = with(UILabel()) {
                $0.font = .systemFont(ofSize: 15, weight: .semibold)
                $0.numberOfLines = 0
                $0.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
            }
            let bodyLabel = with(UILabel()) {
                $0.font = .systemFont(ofSize: 15)
                $0.numberOfLines = 0
                $0.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                $0.setContentHuggingPriority(.defaultHigh, for: .vertical)
            }
            let content = Vertically(titleLabel, bodyLabel) {
                $0.spacing = 2
                $0.alignment = .leading
            }
            let container = VerticalContainer(content, alignment: .fill, insets: .zero)
            
            let material = UIView()
            let visualEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            material.addSubview(visualEffect) {
                $0.anchors.edges.pin()
            }
            material.addSubview(container) {
                $0.anchors.edges.pin(insets: .init(top: 9, left: 12, bottom: 9, right: 14))
            }
            
            material.layer.cornerRadius = 13
            material.layer.masksToBounds = true
            
            let triggerLabel = with(UILabel()) {
                $0.font = .systemFont(ofSize: 13, weight: .regular)
                $0.textColor = .systemOrange
                $0.numberOfLines = 0
            }
            
            let idLabel = with(UILabel()) {
                $0.font = .systemFont(ofSize: 13, weight: .regular)
                $0.textColor = .secondaryLabel
                $0.numberOfLines = 0
            }
            let categoryLabel = with(UILabel()) {
                $0.font = .systemFont(ofSize: 13, weight: .regular)
                $0.textColor = .secondaryLabel
                $0.numberOfLines = 0
            }
            
            let detailsStack = Vertically(triggerLabel, idLabel, categoryLabel) {
                $0.spacing = 2
            }
            let detailsContainer = HorizontalContainer(detailsStack, alignment: .fill, insets: .left(13))
            
            let finalStack = Vertically(material, detailsContainer) {
                $0.spacing = 4
            }
            
            cell.contentView.addSubview(finalStack) {
                $0.anchors.edges.marginsPin()
            }
            
            cell.onReuse { (cell, notif) in
                titleLabel.text = notif.request.content.title
                bodyLabel.text = notif.request.content.body
                triggerLabel.text = notif._dateLabel
                
                var ident = notif.request.identifier
                var simulated = ""
                while ident.hasSuffix("___np_notif_simulation") {
                    ident.removeLast("___np_notif_simulation".count)
                    simulated += " (simulated)"
                }
                idLabel.text = "id: " + ident + simulated
                categoryLabel.text = "category: " + notif.request.content.categoryIdentifier
                
                cell.onSelect(to: self) { (self, cell) in
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.05, repeats: false)
                    let copy = UNNotificationRequest(
                        identifier: notif.request.identifier + "___np_notif_simulation",
                        content: notif.request.content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(copy, withCompletionHandler: nil)
                }
            }
        }
        
        if mode != .delivered {
            tableView.addRowCell { (cell) in
                cell.textLabel?.text = "Show Delivered Notifications"
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.font = .systemFont(ofSize: 16, weight: .heavy)
                cell.textLabel?.text = cell.textLabel?.text?.uppercased()
                cell.textLabel?.textColor = .secondaryLabel
                cell.indentationLevel = 1
            }.withAccessoryType(.disclosureIndicator).onSelect(to: self) { (self, _) in
                let delivered = ScheduledNotificationsViewController(mode: .delivered)
                self.navigationController?.pushViewController(delivered, animated: true)
            }
        }
        
        tableView.onPulledToRefresh(to: self) { (self) in
            self.reload()
        }
        
        reload()
    }
    
    func reload() {
        switch mode {
        case .pending:
            UNUserNotificationCenter.current().getPendingNotificationRequests { (requests) in
                DispatchQueue.main.async {
                    self.requests = requests.sorted(by: UNNotificationTrigger.sortByEarliest(left:right:))
                    self.tableView.reloadData()
                    self.tableView.refreshControl?.endRefreshing()
                }
            }
        case .delivered:
            UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
                DispatchQueue.main.async {
                    self.requests = notifications
                        .filter({ !$0.request.identifier.hasSuffix("___np_notif_simulation") })
                        .sorted(by: { UNNotificationTrigger.sortByEarliest(left: $1, right: $0) })
                    self.tableView.reloadData()
                    self.tableView.refreshControl?.endRefreshing()
                }
            }
        }
    }
}

extension UNNotificationTrigger {
    fileprivate static func sortByEarliest(left: NotificationToShow, right: NotificationToShow) -> Bool {
        let (leftDate, rightDate) = (left._dateToCompare, right._dateToCompare)
        switch (leftDate, rightDate) {
        case (.none, .none):
            return false
        case (.some(let l), .some(let r)):
            return l < r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        }
    }
    
    func _triggerDate() -> Date? {
        switch self {
        case let calendarBased as UNCalendarNotificationTrigger:
            return calendarBased.nextTriggerDate()
        case let intervalBased as UNTimeIntervalNotificationTrigger:
            return intervalBased.nextTriggerDate()
        default:
            return nil
        }
    }
    
    fileprivate var _dateLabel: String? {
        switch self {
        case let calendarBased as UNCalendarNotificationTrigger:
            if let triggerDate = calendarBased.nextTriggerDate() {
                return ScheduledNotificationsViewController.formatter.string(from: triggerDate)
                    + (calendarBased.repeats ? " (repeats)" : "")
            } else {
                return nil
            }
        case let intervalBased as UNTimeIntervalNotificationTrigger:
            if let triggerDate = intervalBased.nextTriggerDate() {
                return ScheduledNotificationsViewController.formatter.string(from: triggerDate)
                    + (intervalBased.repeats ? " (repeats)" : "")
            } else {
                return nil
            }
        case is UNLocationNotificationTrigger:
            return "location based"
        default:
            return nil
        }
    }
}

fileprivate protocol NotificationToShow {
    var _dateLabel: String? { get }
    var trigger: UNNotificationTrigger? { get }
    var request: UNNotificationRequest { get }
    var _dateToCompare: Date? { get }
}

extension UNNotificationRequest: NotificationToShow {
    var _dateLabel: String? {
        return trigger?._dateLabel
    }
    
    var request: UNNotificationRequest {
        return self
    }
    
    var _dateToCompare: Date? {
        return trigger?._triggerDate()
    }
}

extension UNNotification: NotificationToShow {
    var _dateLabel: String? {
        return ScheduledNotificationsViewController.formatter.string(from: date)
    }
    
    var trigger: UNNotificationTrigger? {
        return request.trigger
    }
    
    var _dateToCompare: Date? {
        return date
    }
}

@discardableResult
func with<Obj: AnyObject>(_ object: Obj, _ block: (Obj) -> Void) -> Obj {
    block(object)
    return object
}
