import UIKit

// game configuration using struct
struct GameConfig {
    static let initialGapHeight: CGFloat = 350
    static let minimumGapHeight: CGFloat = 70
    static let gapDecreaseRate: CGFloat = 5  // decrease gap per point scored
    static let gravity: CGFloat = 0.5
    static let birdStartPosition = CGPoint(x: 100, y: 300)
    static let birdSize = CGSize(width: 50, height: 50)
    static let pipeWidth: CGFloat = 60
    static let pipeSpawnInterval: TimeInterval = 2.5
    static let pipeHorizontalSpeed: CGFloat = 2
    static let flapVelocity: CGFloat = -8
}

// score entry struct for leaderboard
struct ScoreEntry: Codable { // encodable and decodable -- for propery lists ==>> easily save the leaderboard scores to UserDefaults and Easily load them scores back from UserDefaults by decoding the data
    let name: String
    let score: Int
}

// bird state struct -->> encapsulating bird properties and behavior
struct BirdState {
    var position: CGPoint
    var velocity: CGFloat
    
    mutating func applyGravity() {
        velocity += GameConfig.gravity
    }
    
    mutating func flap() {
        velocity = GameConfig.flapVelocity
    }
    
    mutating func updatePosition() {
        position.y += velocity
    }
    
    // reset bird to starting position
    mutating func reset() {
        position = GameConfig.birdStartPosition
        velocity = 0
    }
}

// pipe config struct
struct PipeConfig {
    let topPipeHeight: CGFloat
    let bottomPipeY: CGFloat
    let gapHeight: CGFloat
    
    // generate random pipe config
    static func random(for viewHeight: CGFloat, currentScore: Int) -> PipeConfig {
        // calc current gap height based on score
        let gapDecrease = min(CGFloat(currentScore) * GameConfig.gapDecreaseRate, 
                             GameConfig.initialGapHeight - GameConfig.minimumGapHeight)
        let currentGapHeight = GameConfig.initialGapHeight - gapDecrease
        
        let minHeight: CGFloat = 100
        let maxHeight = viewHeight - currentGapHeight - 150
        let topHeight = CGFloat.random(in: minHeight...maxHeight)
        let bottomY = topHeight + currentGapHeight
        
        return PipeConfig(
            topPipeHeight: topHeight,
            bottomPipeY: bottomY,
            gapHeight: currentGapHeight
        )
    }
    
    // computed property to determine difficulty level
    var difficultyLevel: String {
        let percentDifficulty = (GameConfig.initialGapHeight - gapHeight) / (GameConfig.initialGapHeight - GameConfig.minimumGapHeight)
        
        switch percentDifficulty {
        case ..<0.3: return "Easy"
        case 0.3..<0.6: return "Medium"
        case 0.6..<0.9: return "Hard"
        default: return "Extreme"
        }
    }
    
    // сomputed property for difficulty color
    var difficultyColor: UIColor {
        let percentDifficulty = (GameConfig.initialGapHeight - gapHeight) / (GameConfig.initialGapHeight - GameConfig.minimumGapHeight)
        
        switch percentDifficulty {
        case ..<0.3: return .green
        case 0.3..<0.6: return .yellow
        case 0.6..<0.9: return .orange
        default: return .red
        }
    }
}

// UI сonfig struct
struct UIConfig {
    struct Colors {
        static let buttonBackground = UIColor(red: 0, green: 0.5, blue: 0.8, alpha: 0.8)
        static let buttonPressed = UIColor(red: 0, green: 0.4, blue: 0.7, alpha: 0.9)
        static let scoreBackground = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        static let leaderboardBackground = UIColor(white: 0, alpha: 0.8)
        static let gameOverText = UIColor.red
        static let countdownText = UIColor.white
    }
    
    struct Fonts {
        static let scoreFont = UIFont.boldSystemFont(ofSize: 32)
        static let countdownFont = UIFont.boldSystemFont(ofSize: 100)
        static let buttonFont = UIFont.boldSystemFont(ofSize: 30)
        static let gameOverFont = UIFont.boldSystemFont(ofSize: 36)
        static let difficultyFont = UIFont.boldSystemFont(ofSize: 18)
    }
}

class ViewController: UIViewController, UITextFieldDelegate {

    var bird: UIImageView!
    var birdState: BirdState!
    
    var backgroundImageView: UIImageView!
    var scoreLabel: UILabel!
    var score: Int = 0
    var countdownLabel: UILabel!
    var countdownTimer: Timer?
    var countdownValue: Int = 3
    
    // ----- leaderboard components -----
    var leaderboardView: UIView!
    var nameTextField: UITextField!
    var submitButton: UIButton!
    var leaderboardTableView: UITableView!
    var leaderboardScores: [ScoreEntry] = []   // Now using ScoreEntry struct

    var displayLink: CADisplayLink?
    var pipeTimer: Timer?
    var pipes: [UIImageView] = []
    var pipesPassedByBird = Set<UIImageView>()
    var currentPipeConfig: PipeConfig?

    var isGameRunning = false

    // UI
    var startButton: UIButton!
    var gameOverLabel: UILabel!
    var difficultyLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadLeaderboard()
    }

    func setupUI() {
        let safeAreaInsets = view.safeAreaInsets
        
        // background
        backgroundImageView = UIImageView(frame: view.bounds)
        backgroundImageView.image = UIImage(named: "background")
        backgroundImageView.contentMode = .scaleToFill
        view.addSubview(backgroundImageView)
        
        // bird (hidden initially)
        bird = UIImageView(image: UIImage(named: "bird"))
        bird.frame = CGRect(origin: .zero, size: GameConfig.birdSize)
        bird.center = GameConfig.birdStartPosition
        bird.isHidden = true
        view.addSubview(bird)
        
        // initailize bird state
        birdState = BirdState(position: GameConfig.birdStartPosition, velocity: 0)
        
        // set up UI container for HUD elements to ensure they are on top
        let hudContainer = UIView(frame: view.bounds)
        hudContainer.backgroundColor = .clear
        view.addSubview(hudContainer)
        
        // countdown Label - add to HUD container
        countdownLabel = UILabel()
        countdownLabel.text = "3"
        countdownLabel.textAlignment = .center
        countdownLabel.font = UIConfig.Fonts.countdownFont
        countdownLabel.textColor = UIConfig.Colors.countdownText
        countdownLabel.frame = CGRect(x: 0, y: view.frame.height/2 - 100, width: view.frame.width, height: 200)
        countdownLabel.isHidden = true
        countdownLabel.layer.shadowColor = UIColor.black.cgColor
        countdownLabel.layer.shadowOffset = CGSize(width: 2, height: 2)
        countdownLabel.layer.shadowOpacity = 0.8
        countdownLabel.layer.shadowRadius = 3
        hudContainer.addSubview(countdownLabel)
        
        // diff indicator
        difficultyLabel = UILabel()
        difficultyLabel.text = "Gap: Easy"
        difficultyLabel.textAlignment = .center
        difficultyLabel.font = UIConfig.Fonts.difficultyFont
        difficultyLabel.textColor = .white
        difficultyLabel.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        difficultyLabel.layer.cornerRadius = 10
        difficultyLabel.layer.masksToBounds = true
        difficultyLabel.frame = CGRect(x: view.frame.width - 110, y: 75, width: 100, height: 30)
        difficultyLabel.isHidden = true
        difficultyLabel.layer.zPosition = 100
        hudContainer.addSubview(difficultyLabel)

        // start btn with effects - add to HUD container
        startButton = UIButton(type: .system)
        startButton.setTitle("Start Game", for: .normal)
        startButton.backgroundColor = UIConfig.Colors.buttonBackground
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = UIConfig.Fonts.buttonFont
        startButton.layer.cornerRadius = 15
        startButton.frame = CGRect(x: view.frame.width/2 - 100, y: view.frame.height/2 - 30, width: 200, height: 60)
        
        // btn effects
        startButton.showsTouchWhenHighlighted = true
        
        // custom hover and pressed states
        startButton.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        startButton.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        startButton.addTarget(self, action: #selector(startCountdown), for: .touchUpInside)
        
        hudContainer.addSubview(startButton)

        // Game Over label - add to HUD container
        gameOverLabel = UILabel()
        gameOverLabel.text = "Game Over!"
        gameOverLabel.textAlignment = .center
        gameOverLabel.font = UIConfig.Fonts.gameOverFont
        gameOverLabel.textColor = UIConfig.Colors.gameOverText
        gameOverLabel.frame = CGRect(x: 0, y: view.frame.height/2 - 150, width: view.frame.width, height: 60)
        gameOverLabel.isHidden = true
        hudContainer.addSubview(gameOverLabel)

        // score label - add to HUD container
        scoreLabel = UILabel()
        scoreLabel.text = "Score: 0"
        scoreLabel.textAlignment = .center
        scoreLabel.font = UIConfig.Fonts.scoreFont
        scoreLabel.textColor = .white
        scoreLabel.backgroundColor = UIConfig.Colors.scoreBackground
        scoreLabel.layer.cornerRadius = 15
        scoreLabel.layer.masksToBounds = true
        scoreLabel.frame = CGRect(x: view.frame.width/2 - 75, y: 75, width: 150, height: 50)
        scoreLabel.isHidden = true
        scoreLabel.layer.zPosition = 200000 // Ensure it's on top
        hudContainer.addSubview(scoreLabel)
        
        // setup Leaderboard
        setupLeaderboardUI()

        // tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(flap))
        view.addGestureRecognizer(tapGesture)
    }
    
    func setupLeaderboardUI() {
        // leaderboard container
        leaderboardView = UIView(frame: CGRect(x: view.frame.width/2 - 150, y: view.frame.height/2 - 200, width: 300, height: 400))
        leaderboardView.backgroundColor = UIConfig.Colors.leaderboardBackground
        leaderboardView.layer.cornerRadius = 20
        leaderboardView.isHidden = true
        leaderboardView.layer.zPosition = 101 // higher than score
        view.addSubview(leaderboardView)
        
        // title
        let titleLabel = UILabel(frame: CGRect(x: 0, y: 20, width: 300, height: 30))
        titleLabel.text = "LEADERBOARD"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textColor = .white
        leaderboardView.addSubview(titleLabel)
        
        // your score
        let yourScoreLabel = UILabel(frame: CGRect(x: 20, y: 60, width: 260, height: 30))
        yourScoreLabel.text = "Your Score:"
        yourScoreLabel.textAlignment = .left
        yourScoreLabel.font = UIFont.systemFont(ofSize: 18)
        yourScoreLabel.textColor = .white
        leaderboardView.addSubview(yourScoreLabel)
        
        // name input field
        nameTextField = UITextField(frame: CGRect(x: 20, y: 100, width: 260, height: 40))
        nameTextField.placeholder = "Enter your name"
        nameTextField.backgroundColor = .white
        nameTextField.textColor = .black
        nameTextField.layer.cornerRadius = 10
        nameTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 40))
        nameTextField.leftViewMode = .always
        nameTextField.delegate = self
        nameTextField.returnKeyType = .done
        leaderboardView.addSubview(nameTextField)
        
        // submit btn
        submitButton = UIButton(type: .system)
        submitButton.setTitle("Submit Score", for: .normal)
        submitButton.backgroundColor = UIColor(red: 0, green: 0.7, blue: 0.3, alpha: 1)
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        submitButton.layer.cornerRadius = 10
        submitButton.frame = CGRect(x: 20, y: 150, width: 260, height: 40)
        submitButton.addTarget(self, action: #selector(submitScore), for: .touchUpInside)
        leaderboardView.addSubview(submitButton)
        
        // table view for scores
        leaderboardTableView = UITableView(frame: CGRect(x: 20, y: 200, width: 260, height: 150))
        leaderboardTableView.backgroundColor = .clear
        leaderboardTableView.register(UITableViewCell.self, forCellReuseIdentifier: "scoreCell")
        leaderboardTableView.dataSource = self
        leaderboardTableView.delegate = self
        leaderboardTableView.layer.cornerRadius = 10
        leaderboardView.addSubview(leaderboardTableView)
        
        // close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.backgroundColor = UIColor(red: 0.8, green: 0, blue: 0, alpha: 0.8)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        closeButton.layer.cornerRadius = 10
        closeButton.frame = CGRect(x: 20, y: 360, width: 260, height: 30)
        closeButton.addTarget(self, action: #selector(closeLeaderboard), for: .touchUpInside)
        leaderboardView.addSubview(closeButton)
    }
    
    // game ctrl methods    
    @objc func startCountdown() {
        // hide start btn -->> show countdown
        startButton.isHidden = true
        countdownLabel.isHidden = false
        countdownValue = 3
        countdownLabel.text = "\(countdownValue)"
        
        // place bird in starting position BUT do not start movement yet
        bird.isHidden = false
        birdState = BirdState(position: GameConfig.birdStartPosition, velocity: 0)
        bird.center = birdState.position
        
        // start countdown timer
        countdownTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
    }
    
    @objc func updateCountdown() {
        countdownValue -= 1
        
        // animate countdown number
        UIView.animate(withDuration: 0.2, animations: {
            self.countdownLabel.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.countdownLabel.transform = CGAffineTransform.identity
            }
        }
        
        if countdownValue > 0 { countdownLabel.text = "\(countdownValue)"} 
        else { // countdown finished -->> START the GAME
            countdownTimer?.invalidate()
            countdownLabel.isHidden = true
            startGame()
        }
    }
    
    @objc func startGame() {
        // reset state
        isGameRunning = true
        birdState.reset()
        score = 0
        updateScoreLabel()
        
        pipes.forEach { $0.removeFromSuperview() }
        pipes.removeAll()
        pipesPassedByBird.removeAll()

        scoreLabel.isHidden = false
        difficultyLabel.isHidden = false
        difficultyLabel.text = "Gap: Easy"
        difficultyLabel.textColor = .green
        gameOverLabel.isHidden = true
        
        // start game loop
        displayLink = CADisplayLink(target: self, selector: #selector(gameLoop))
        displayLink?.add(to: .current, forMode: .default)

        pipeTimer = Timer.scheduledTimer(timeInterval: GameConfig.pipeSpawnInterval, target: self, selector: #selector(spawnPipes), userInfo: nil, repeats: true)
    }
    
    @objc func gameLoop() {
        // upd bird pos using the struct methods
        birdState.applyGravity()
        birdState.updatePosition()
        bird.center = birdState.position

        // check screen boundaries
        if bird.frame.minY <= 0 || bird.frame.maxY >= view.frame.height {
            gameOver()
            return
        }

        // move pipes n check collisions
        for (index, pipe) in pipes.enumerated() {
            pipe.center.x -= GameConfig.pipeHorizontalSpeed

            if bird.frame.intersects(pipe.frame){ // collision check
                gameOver()
                return
            }
            
            // add score when passing pipe -- ONLY for half/top pipes to avoid double count
            if index % 2 == 0 && !pipesPassedByBird.contains(pipe) && pipe.center.x < bird.center.x {
                pipesPassedByBird.insert(pipe)
                score += 1
                updateScoreLabel()
                
                // upd difficulty display using the current pipe config
                updateDifficultyDisplay()
            }
        }

        // remove off screen pipes | to avoid game lagging
        pipes.removeAll(where: { pipe in
            if pipe.frame.maxX < 0 {
                pipesPassedByBird.remove(pipe)
                pipe.removeFromSuperview()
                return true
            }
            return false
        })
    }
    
    func updateDifficultyDisplay() {
        // generate a current pipe config based on score to get difficulty info
        let pipeConfig = PipeConfig.random(for: view.frame.height, currentScore: score)
        
        // upd the difficulty label based on the pipe config
        difficultyLabel.text = "Gap: \(pipeConfig.difficultyLevel)"
        difficultyLabel.textColor = pipeConfig.difficultyColor
        
        // if gap has reached min => flash the score briefly to indicate maximum difficulty
        if pipeConfig.gapHeight <= GameConfig.minimumGapHeight {
            UIView.animate(withDuration: 1, animations: {
                self.scoreLabel.backgroundColor = UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.7)
            }) { _ in
                UIView.animate(withDuration: 1) {
                    self.scoreLabel.backgroundColor = UIConfig.Colors.scoreBackground
                }
            }
        }
    }
    
    @objc func spawnPipes() {
        // use PipeConfig struct to generate a random pipe configuration
        let pipeConfig = PipeConfig.random(for: view.frame.height, currentScore: score)
        currentPipeConfig = pipeConfig
        
        // top pipe is FLIPPED bottom pipe uW
        let topPipe = UIImageView(frame: CGRect(x: view.frame.width, y: 0, 
                                              width: GameConfig.pipeWidth, height: pipeConfig.topPipeHeight))
        topPipe.image = UIImage(named: "pipe")
        topPipe.contentMode = UIView.ContentMode.scaleToFill
        // FLIP ITTTTTTTTTTTTT
        topPipe.transform = CGAffineTransform(scaleX: 1, y: -1)
        
        // bottom pipe is straight
        let bottomPipe = UIImageView(frame: CGRect(x: view.frame.width, y: pipeConfig.bottomPipeY, 
                                                 width: GameConfig.pipeWidth, 
                                                 height: view.frame.height - pipeConfig.bottomPipeY))
        bottomPipe.image = UIImage(named: "pipe")
        bottomPipe.contentMode = UIView.ContentMode.scaleToFill

        view.addSubview(topPipe)
        view.addSubview(bottomPipe)

        pipes.append(topPipe)
        pipes.append(bottomPipe)
    }
    
    @objc func buttonTouchDown(_ sender: UIButton) {
        // btn pressed effect
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            sender.backgroundColor = UIConfig.Colors.buttonPressed
        }
    }
    
    @objc func buttonTouchUp(_ sender: UIButton) {
        // btn released effect
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform.identity
            sender.backgroundColor = UIConfig.Colors.buttonBackground
        }
    }
    
    @objc func gameOver() {
        isGameRunning = false
        displayLink?.invalidate()
        pipeTimer?.invalidate()
        gameOverLabel.isHidden = false
        
        leaderboardView.isHidden = false // displya leaderboard instead of restart btn
        
        nameTextField.becomeFirstResponder() // focuse on name field
        
        // upd the score label in the leaderboard
        if let yourScoreLabel = leaderboardView.subviews.first(where: { ($0 as? UILabel)?.text?.hasPrefix("Your Score") == true }) as? UILabel {
            yourScoreLabel.text = "Your Score: \(score)"
        }
    }
    
    @objc func submitScore() {
        guard let name = nameTextField.text, !name.isEmpty else {
            // alert for empty name | name submission is required
            let alert = UIAlertController(title: "Name Required", message: "Please enter your name to submit your score", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        // add score to leaderboard using ScoreEntry struct
        let entry = ScoreEntry(name: name, score: score)
        leaderboardScores.append(entry)
        
        // sort by score DESC order -- higest to lowest
        leaderboardScores.sort { $0.score > $1.score }
        
        // limit to top 10
        if leaderboardScores.count > 10 {
            leaderboardScores = Array(leaderboardScores.prefix(10))
        }
        
        // reload the table
        leaderboardTableView.reloadData()
        
        // dismiss keyboard
        nameTextField.resignFirstResponder()
        
        // save leaderboard
        saveLeaderboard()
    }
    
    @objc func closeLeaderboard() {
        leaderboardView.isHidden = true
        startButton.setTitle("Restart", for: .normal)
        startButton.isHidden = false
    }
    
    @objc func flap() {
        if isGameRunning {
            birdState.flap()
        }
    }
    
    func updateScoreLabel() {
        scoreLabel.text = "Score: \(score)"
    }
    
    func saveLeaderboard() {
        // encode ScoreEntry structs for storage =>> since we made ScoreEntry Codable ==>> we can use JSONEncoder)
        if let encoded = try? JSONEncoder().encode(leaderboardScores) {
            UserDefaults.standard.set(encoded, forKey: "leaderboard")
        }
    }
    
    func loadLeaderboard() {
        // load and decode ScoreEntry structs
        if let savedData = UserDefaults.standard.data(forKey: "leaderboard"),
           let decodedEntries = try? JSONDecoder().decode([ScoreEntry].self, from: savedData) {
            leaderboardScores = decodedEntries
        } else {
            // fallback to old format if needed
            if let savedLeaderboard = UserDefaults.standard.object(forKey: "leaderboard") as? [[String: Any]] {
                leaderboardScores = savedLeaderboard.compactMap { dict in
                    if let name = dict["name"] as? String,
                       let score = dict["score"] as? Int {
                        return ScoreEntry(name: name, score: score)
                    }
                    return nil
                }
            }
        }
        
        leaderboardScores.sort { $0.score > $1.score }
    }
    
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitScore()
        return true
    }
}


extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return leaderboardScores.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scoreCell", for: indexPath)
        
        // config cell using ScoreEntry struct
        let entry = leaderboardScores[indexPath.row]
        cell.textLabel?.text = "\(indexPath.row + 1). \(entry.name): \(entry.score)"
        cell.textLabel?.textColor = .white
        cell.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        
        // highlight cur score
        if entry.score == score && nameTextField.text == entry.name {
            cell.backgroundColor = UIColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.7)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
