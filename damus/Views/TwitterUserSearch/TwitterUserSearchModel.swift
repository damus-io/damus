//
//  TwitterUserSearchModel.swift
//  damus
//
//  Created by Joel Klabo on 5/10/23.
//

import Foundation
import Combine

struct TwitterUser: Codable, Identifiable {
    let id: String
    let twitter_handle: String
    let profile: String

    enum CodingKeys: String, CodingKey {
        case id = "pubkey"
        case twitter_handle
        case profile
    }
}

enum TwitterViewState {
    case empty
    case results([TwitterUser])
    case loading
    case error(String)
}


struct TwitterUserResponse: Codable {
    let result: [TwitterUser]
}

class TwitterUserSearchModel: ObservableObject {
    
    @Published var searchText: String = ""
    @Published var state: TwitterViewState = .empty
    
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = $searchText.debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { searchTerm in
                guard !searchTerm.isEmpty else { return }
                self.state = .loading
                self.findFollowers(handle: searchTerm) { result in
                    // Need to publish on the main thread
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let users):
                            self.state = .results(users)
                        case .failure(let error):
                            self.state = .error(error.localizedDescription)
                        }
                    }
                }
            }
    }
    
    func findFollowers(handle: String, completion: @escaping (Result<[TwitterUser], Error>) -> Void) {
        guard let url = URL(string: "https://getcurrent.io/followuser?twitterhandle=\(handle)") else {
            print("Invalid URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let data = data {
                let decoder = JSONDecoder()
                do {
                    let twitterUserResponse = try decoder.decode(TwitterUserResponse.self, from: data)
                    completion(.success(twitterUserResponse.result))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        task.resume()
    }
}

