//
//  FirstViewController.swift
//  KituraStepTracker
//
//  Created by Joe Anthony Peter Amanse on 5/23/18.
//  Copyright © 2018 Joe Anthony Peter Amanse. All rights reserved.
//

import UIKit
import KituraKit
import CoreData
import HealthKit
import CoreMotion
import CoreImage

struct UpdateUserStepsRequest: Codable {
    var steps: Int
}

class UserViewController: UIViewController {

    @IBOutlet weak var userFitcoins: UILabel!
    @IBOutlet weak var userSteps: UILabel!
    @IBOutlet weak var userScrollView: UIScrollView!
    @IBOutlet weak var userImage: UIImageView!
    @IBOutlet weak var userName: UILabel!
    @IBOutlet weak var userId: UILabel!
    var refreshControl: UIRefreshControl?
    let KituraBackendUrl = "https://tokyokubedemo01.jp-tok.containers.appdomain.cloud"
    var sendingInProgress: Bool = false
    
    var pedometer = CMPedometer()
    var currentUser: SavedUser?
    var userBackend: User?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view, typically from a nib.
        initImageView()
        
        // Clear labels
        self.userName.text = ""
        self.userId.text = ""
        self.userSteps.text = ""
        self.userFitcoins.text = ""
        
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        self.userScrollView.refreshControl = refreshControl
        
        currentUser = (UIApplication.shared.delegate as! AppDelegate).getUserFromLocal()
        self.getCurrentSteps()
        self.startUpdatingSteps()
        
        if let user = currentUser {
            self.getUserWith(userId: user.userId!)
        }
    }
    
    func getUserWith(userId: String, group: DispatchGroup? = nil) {
        group?.enter()
        guard let client = KituraKit(baseURL: self.KituraBackendUrl) else {
            print("Error creating KituraKit client")
            group?.leave()
            return
        }
        
        client.get("/users/\(userId)") { (user: User?, error: Error?) in
            guard error == nil else {
                print("Error getting user from Kitura: \(error!)")
                group?.leave()
                return
            }
            
            if let user = user {
                print(user)
                self.userBackend = user
                self.updateViewWith(userId: user.userId, name: user.name, image: user.image, fitcoins: user.fitcoin)
            }
            
            group?.leave()
        }
    }
    
    func updateViewWith(userId: String, name: String, image: Data, fitcoins: Int) {
        DispatchQueue.main.async {
            self.userId.text = userId
            self.userName.text = name
            self.userImage.image = UIImage(data: image)
            self.userFitcoins.text = "\(fitcoins) fitcoins"
            self.userImage.layer.cornerRadius = 75
        }
    }
    
    func getCurrentSteps(_ group: DispatchGroup? = nil) {
        group?.enter()
        if let user = self.currentUser {
            pedometer.queryPedometerData(from: user.startDate!, to: Date()) { (pedometerData, error) in
                if let error = error {
                    print(error)
                }
                
                if let pedometerData = pedometerData {
                    DispatchQueue.main.async {
                        self.userSteps.text = String(describing: pedometerData.numberOfSteps) + " steps"
                    }
                }
                group?.leave()
            }
        } else {
            group?.leave()
        }
    }
    
    func startUpdatingSteps(_ group: DispatchGroup? = nil) {
        group?.enter()
        
        if let user = self.currentUser {
            pedometer.startUpdates(from: user.startDate!) { (pedometerData, error) in
                if let error = error {
                    print(error)
                }
                
                if let pedometerData = pedometerData {
                    DispatchQueue.main.async {
                        self.userSteps.text = String(describing: pedometerData.numberOfSteps) + " steps"
                    }
                    
                    if let userBackend = self.userBackend {
                        if self.sendingInProgress == false {
                            if (pedometerData.numberOfSteps.intValue - userBackend.stepsConvertedToFitcoin) >= 100 {
                                print("ready to send")
                                self.sendingInProgress = true
                                
                                // insert function here to PUT to kitura
                                self.updateUserSteps(userId: userBackend.userId, steps: pedometerData.numberOfSteps.intValue)
                            }
                        }
                    }
                }
                group?.leave()
            }
        } else {
            group?.leave()
        }
    }
    
    func updateUserSteps(userId: String, steps: Int) {
        guard let client = KituraKit(baseURL: self.KituraBackendUrl) else {
            print("Error creating KituraKit client")
            self.sendingInProgress = false
            return
        }
        
        client.put("/users", identifier: userId, data: UpdateUserStepsRequest(steps: steps)) { (userCompact: UserCompact?, error: RequestError?) in
            guard error == nil else {
                print("Error getting user from Kitura: \(error!)")
                self.sendingInProgress = false
                return
            }
            
            if let user = userCompact {
                self.getUserWith(userId: user.userId)
            }
            
            self.sendingInProgress = false
        }
    }
    
    @objc func refresh() {
        if let user = self.currentUser {
            // refresh data
            
            let group = DispatchGroup()
            
            getUserWith(userId: user.userId!, group: group)
            getCurrentSteps(group)
            
            group.notify(queue: .main) {
                DispatchQueue.main.async {
                    if (self.refreshControl?.isRefreshing)! {
                        self.refreshControl?.endRefreshing()
                    }
                }
            }
        } else {
            self.currentUser = (UIApplication.shared.delegate as! AppDelegate).getUserFromLocal()
            DispatchQueue.main.async {
                if (self.refreshControl?.isRefreshing)! {
                    self.refreshControl?.endRefreshing()
                }
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    private func initImageView(){
        //会員番号を取得
        let memberid = getMemberId()
        
        // NSString から NSDataへ変換
        let data = memberid.data(using: String.Encoding.utf8)!
        
        // QRコード生成のフィルター
        // NSData型でデーターを用意
        // inputCorrectionLevelは、誤り訂正レベル
        let qr = CIFilter(name: "CIQRCodeGenerator", withInputParameters: ["inputMessage": data, "inputCorrectionLevel": "M"])!
        
        
        let sizeTransform = CGAffineTransform(scaleX: 10, y: 10)
        let qrImage = qr.outputImage!.transformed(by: sizeTransform)
       
        // UIImage インスタンスの生成
        // UIImageView 初期化
        let uiimage = UIImage(ciImage:qrImage)
        let imageView = UIImageView(image:uiimage)
        
        // 画面の横幅を取得
        let screenWidth:CGFloat = view.frame.size.width
        let screenHeight:CGFloat = view.frame.size.height
        
        // 画像の中心を画面の中心に設定
        imageView.center = CGPoint(x:screenWidth/2, y:screenHeight/1.5)
        
        // UIImageViewのインスタンスをビューに追加
        self.view.addSubview(imageView)
        
    }
    
    private func getMemberId() -> String {
        // 会員番号を生成するロジックを適宜実装して下さい。
        // ここではリテラルで返します。
        let memberid = "HRQ01-34345-9FH0J1-11111"
        
        return memberid
    }
}

