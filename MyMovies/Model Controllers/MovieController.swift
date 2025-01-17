//
//  MovieController.swift
//  MyMovies
//
//  Created by Spencer Curtis on 8/17/18.
//  Copyright © 2018 Lambda School. All rights reserved.
//

import Foundation
import CoreData

enum HTTPMethod: String {
    
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
    
}

class MovieController {

    init() {
        fetchMoviesFromServer()
    }
    
    private let apiKey = "4cc920dab8b729a619647ccc4d191d5e"
    private let baseURL = URL(string: "https://api.themoviedb.org/3/search/movie")!
    private let firebaseBaseURL = URL(string: "https://movies-2ce7e.firebaseio.com/")!
   // MARK: Search For Movie
    func searchForMovie(with searchTerm: String, completion: @escaping (Error?) -> Void) {
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        
        let queryParameters = ["query": searchTerm,
                               "api_key": apiKey]
        
        components?.queryItems = queryParameters.map({URLQueryItem(name: $0.key, value: $0.value)})
        
        guard let requestURL = components?.url else {
            completion(NSError())
            return
        }
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            
            if let error = error {
                NSLog("Error searching for movie with search term \(searchTerm): \(error)")
                completion(error)
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from data task")
                completion(NSError())
                return
            }
            
            do {
                let movieRepresentations = try JSONDecoder().decode(MovieRepresentations.self, from: data).results
                self.searchedMovies = movieRepresentations
                completion(nil)
            } catch {
                NSLog("Error decoding JSON data: \(error)")
                completion(error)
            }
        }.resume()
    }
    
    // MARK: - Properties
    
    var searchedMovies: [MovieRepresentation] = []


    // MARK: Add Movie

    func addMovie(movieRepresentation: MovieRepresentation, context: NSManagedObjectContext = CoreDataStack.shared.mainContext) {
        context.performAndWait {
            guard let movie = Movie(movieRepresentation: movieRepresentation, context: context) else { return }

            do {
                try CoreDataStack.shared.save(context: context)
            } catch {
                NSLog("Error when saving context when adding Movie: \(error)")
            }
            put(movie: movie)
        }
    }
// MARK: Update Has Watched
    func updateHasWatched(movie: Movie, hasWatched: Bool, context: NSManagedObjectContext = CoreDataStack.shared.mainContext) {
        context.performAndWait {
            movie.hasWatched = hasWatched

            do {
                try CoreDataStack.shared.save(context: context)
            } catch {
                NSLog("Error when saving context when updating Movie: \(error)")
            }
            put(movie: movie)
        }
    }
// MARK: Delete Movie
    func deleteMovie(movie: Movie, context: NSManagedObjectContext = CoreDataStack.shared.mainContext) {
        deleteMovieFromServer(movie: movie)
        context.performAndWait {
            let moc = CoreDataStack.shared.mainContext
            moc.delete(movie)

            do {
                try CoreDataStack.shared.save(context: context)
            } catch {
                NSLog("Error when saving context when deleting Movie: \(error)")
            }
        }
    }

}


extension MovieController {
// MARK: Movie/predicate
    func movie(for identifier: UUID, in context: NSManagedObjectContext) -> Movie? {
        // Filter amd find any task with the identifier we give it
        let predicate = NSPredicate(format: "identifier == %@", identifier as NSUUID)

        let fetchRequest: NSFetchRequest<Movie> = Movie.fetchRequest()
        fetchRequest.predicate = predicate

        var task: Movie? = nil
        context.performAndWait {
            do {
                task = try context.fetch(fetchRequest).first
            } catch {
                NSLog("Error fetching movie for identifier: \(error)")
            }
        }
        return task
    }
// MARK: PUT func
    func put(movie: Movie, completion: @escaping(Error?) -> Void = { _ in }) {
        guard let identifier = movie.identifier else { return }
        let requestURL = firebaseBaseURL
            .appendingPathComponent(identifier.uuidString)
            .appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.put.rawValue

        do {
            let movieData = try JSONEncoder().encode(movie.movieRepresentation)
            request.httpBody = movieData
        } catch {
            NSLog("Error encoding movie representation: \(error)")
            completion(error)
            return
        }

        URLSession.shared.dataTask(with: request) { (_, _, error) in
            if let error = error {
                NSLog("Error PUTing movie representation to server: \(error)")
            }
            completion(nil)
            }.resume()
    }
// MARK: Delete from server
    func deleteMovieFromServer(movie: Movie, completion: @escaping(Error?) -> Void = { _ in }) {
        guard let identifier = movie.identifier else {
            completion(nil)
            return
        }

        let requestURL = firebaseBaseURL
            .appendingPathComponent(identifier.uuidString)
            .appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.delete.rawValue

        URLSession.shared.dataTask(with: request) { (_, _, error) in
            if let error = error {
                NSLog("Error deleting movie: \(error)")
            }
            completion(nil)
            }.resume()
    }
// MARK: Fetch from Server
    func fetchMoviesFromServer(completion: @escaping(Error?) -> Void = { _ in }) {
        let requestURL = firebaseBaseURL.appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.get.rawValue

        URLSession.shared.dataTask(with: request) { (data, _, error) in
            if let error = error {
                NSLog("Error fetching single Movie: \(error)")
                return
            }

            guard let data = data else {
                NSLog("No data returned from data task")
                return
            }

            do {
                let movieData = try JSONDecoder().decode([String: MovieRepresentation].self, from: data)
                let movies = Array(movieData.values)
                let backgroundContext = CoreDataStack.shared.container.newBackgroundContext()
                self.updatePersistentStore(with: movies, context: backgroundContext)
            } catch {
                NSLog("Error decoding Movie Representations: \(error)")
            }
            completion(nil)
            }.resume()
    }

    //Mark: Update func
    func update(movie: Movie, movieRepresentation: MovieRepresentation) {
        guard let hasWatched = movieRepresentation.hasWatched else { return }
        movie.hasWatched = hasWatched
        movie.identifier = movieRepresentation.identifier
    }

    // MARK: Update Persistent Store
    func updatePersistentStore(with movieRepresentations: [MovieRepresentation], context: NSManagedObjectContext) {
        context.performAndWait {
            for movieRepresentation in movieRepresentations {
                guard let identifier = movieRepresentation.identifier else { continue }
                let movie = self.fetchingSingleMovieFromPersistentStore(identifier: identifier, context: context)

                if let movie = movie {
                    if movieRepresentation != movie {
                        self.update(movie: movie, movieRepresentation: movieRepresentation)
                    }
                } else {
                    Movie(movieRepresentation: movieRepresentation, context: context)
                }
            }
        }

        do {
            try CoreDataStack.shared.save(context: context)
        } catch {
            NSLog("Error saving context when updating Persistent Store: \(error)")
            context.reset()
        }
    }

    // MARK: Fetch from Persistent Store
    func fetchingSingleMovieFromPersistentStore(identifier: UUID, context: NSManagedObjectContext) -> Movie? {
        let predicate = NSPredicate(format: "identifier == %@", identifier as CVarArg)
        let fetchRequest: NSFetchRequest<Movie> = Movie.fetchRequest()
        fetchRequest.predicate = predicate

        var movie: Movie? = nil

        context.performAndWait {
            do {
                movie = try context.fetch(fetchRequest).first
            } catch {
                NSLog("Error fetching movie")
            }
        }
        return movie
    }
}

