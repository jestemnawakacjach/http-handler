//
//  HttpHandler.swift
//  http-handler
//
//  Created by Karol Wawrzyniak on 18/10/2018.
//  Copyright © 2018 Karol Wawrzyniak. All rights reserved.
//

import Foundation

public typealias CompletionBlock<T> = (T?, Error?) -> Void

public enum RequestType {
    case regular
    case multipart
}

public enum Result<T> {
    case success(T)
    case failure(Error)
}

public protocol IHTTPHandlerRequest {

    func endPoint() -> String

    func method() -> String

    func parameters() -> Dictionary<String, Any>?

    func headers() -> Dictionary<String, String>

    func type() -> RequestType

}

public protocol IHTTPHandlerResponseDecoder {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

public class JSONResponseDecoder: IHTTPHandlerResponseDecoder {

    public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        let jsonDecoder = JSONDecoder()
        return try jsonDecoder.decode(type, from: data)
    }

}

public enum HttpHandlerError: Error {
    case WrongStatusCode(message: String?)
    case ServerResponseNotParseable(message: String?)
    case NotHttpResponse(message: String?)
    case NoDataFromServer
    case NotExpetedDatastructureFromServer(message: String?)
    case ServerResponseIsNotUnboxableDictionary(message: String?)
    case ServerReportedUnsuccessfulOperation
    case ServerResponseReturnedError(errors: String?)
    case custom(message: String)
}

extension HttpHandlerError: LocalizedError {

    private func concatMessage(error: String, message: String?) -> String {

        var result = error

        if let m = message {
            result.append(" : ")
            result.append(m)
        }

        return result
    }

    public var errorDescription: String? {
        switch self {

        case .NotHttpResponse(message: let message):

            return concatMessage(error: NSLocalizedString("Not http response", comment: ""), message: message)

        case .WrongStatusCode(message: let message):

            return concatMessage(error: NSLocalizedString("Wrong http status code", comment: ""), message: message)

        case .ServerResponseNotParseable(message: let message):

            return concatMessage(error: NSLocalizedString("Bad server response - not parsable", comment: ""), message: message)

        case .NoDataFromServer:
            return NSLocalizedString("No data from server", comment: "")

        case .NotExpetedDatastructureFromServer(message: let message):

            return concatMessage(error: NSLocalizedString("Not expected data structure from server", comment: ""), message: message)

        case .ServerResponseIsNotUnboxableDictionary(message: let message):

            return concatMessage(error: NSLocalizedString("Server response is not unboxable", comment: ""), message: message)

        case .ServerReportedUnsuccessfulOperation:
            return NSLocalizedString("Server reported unsuccessful operation", comment: "")

        case .ServerResponseReturnedError(errors: let errors):

            return concatMessage(error: NSLocalizedString("Server response is not unboxable", comment: ""), message: errors)
        case .custom(let message):
            return message
        }
    }

}

public protocol IHTTPHandler: class {

    func makeDecodable<T:Decodable>(request: IHTTPHandlerRequest, completion: @escaping (Result<T>) -> Void)

    func makeDecodable<T:Decodable>(request: IHTTPHandlerRequest, decoder: IHTTPHandlerResponseDecoder, completion: @escaping (Result<T>) -> Void)

    func make<T>(request: IHTTPHandlerRequest, completion: @escaping (T?, Error?) -> Void)

    func make(request: IHTTPHandlerRequest, completion: @escaping ([AnyHashable: Any]?, [AnyHashable: Any], Error?) -> Void)

}

public protocol IHTTPRequestBodyCreator {
    func buildBody(request: IHTTPHandlerRequest) throws -> Data?
}


public class JSONBodyCreator: IHTTPRequestBodyCreator {

    public init() { }

    public func buildBody(request: IHTTPHandlerRequest) throws -> Data? {

        if let params = request.parameters(), request.method() != "GET" {
            let paramsData = try JSONSerialization.data(withJSONObject: params, options: JSONSerialization.WritingOptions(rawValue: 0))
            return paramsData
        } else {
            return nil
        }
    }
}


open class HTTPHandler: IHTTPHandler {

    let urlSession: URLSession
    let baseURL: String

    public init(baseURL: String) {
        self.baseURL = baseURL
        self.urlSession = URLSession(configuration: .default)
    }

    fileprivate func handleResponse<T: Decodable>(_ error: Error?,
                                                _ response: HTTPURLResponse,
                                                _ data: Data?,
                                                _ decoder: IHTTPHandlerResponseDecoder,
                                                completion: @escaping (T?, [AnyHashable: Any], Error?) -> Void) {
        DispatchQueue.main.async {

            if error != nil {
                completion(nil, response.allHeaderFields, error)
                return
            }

            if let dataToParse = data {

                let successResponseCodes = [200, 201, 202, 203, 204]
                guard successResponseCodes.contains(response.statusCode) else {
                    completion(nil, response.allHeaderFields, HttpHandlerError.WrongStatusCode(message: response.debugDescription))
                    return
                }

                do {
                    let parsedData = try decoder.decode(T.self, from: dataToParse)
                    completion(parsedData, response.allHeaderFields, error)
                } catch {
                    let jsonString = String(data: dataToParse, encoding: String.Encoding.utf8)
                    completion(nil, response.allHeaderFields, HttpHandlerError.ServerResponseNotParseable(message: jsonString))
                }

            } else {
                completion(nil, response.allHeaderFields, HttpHandlerError.NoDataFromServer)
            }

        }
    }

    fileprivate func handleResponse<T>(_ error: Error?, _ response: HTTPURLResponse, _ data: Data?, completion: @escaping (T?, [AnyHashable: Any], Error?) -> Void) {
        DispatchQueue.main.async {

            if error != nil {
                completion(nil, response.allHeaderFields, error)
                return
            }

            if let dataToParse = data {

                guard response.statusCode == 200 else {
                    completion(nil, response.allHeaderFields, HttpHandlerError.WrongStatusCode(message: response.debugDescription))
                    return
                }

                guard let parsedData = try? JSONSerialization.jsonObject(with: dataToParse) else {
                    let jsonString = String(data: dataToParse, encoding: String.Encoding.utf8)
                    completion(nil, response.allHeaderFields, HttpHandlerError.ServerResponseNotParseable(message: jsonString))
                    return
                }

                if let parsedData = parsedData as? T {
                    completion(parsedData, response.allHeaderFields, error)
                } else {
                    let jsonString = String(data: dataToParse, encoding: String.Encoding.utf8)
                    completion(nil, response.allHeaderFields, HttpHandlerError.ServerResponseNotParseable(message: jsonString))
                }

            } else {
                completion(nil, response.allHeaderFields, HttpHandlerError.NoDataFromServer)
            }

        }
    }

    private static var numberOfCallsToSetVisible: Int = 0

    static func setVisibleActivitiIndicator(visible: Bool) {
        if visible {
            HTTPHandler.numberOfCallsToSetVisible = HTTPHandler.numberOfCallsToSetVisible + 1
        } else {
            HTTPHandler.numberOfCallsToSetVisible = HTTPHandler.numberOfCallsToSetVisible - 1
        }

        DispatchQueue.main.async {
            UIApplication.shared.isNetworkActivityIndicatorVisible = HTTPHandler.numberOfCallsToSetVisible > 0
        }
    }

    public func decorateRequest(_ request: inout URLRequest,
                                handlerRequest: IHTTPHandlerRequest,
                                bodyCreator: IHTTPRequestBodyCreator? = JSONBodyCreator()) throws {

        request.httpMethod = handlerRequest.method()

        let headers = handlerRequest.headers()

        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let body = try bodyCreator?.buildBody(request: handlerRequest)

        request.httpBody = body
    }

    func run<T: Decodable>(request: IHTTPHandlerRequest,
                         decoder: IHTTPHandlerResponseDecoder, completion: @escaping (T?, [AnyHashable: Any], Error?) -> Void) {

        guard let url = URL(string: self.baseURL + request.endPoint()) else { return }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)

        urlRequest.httpMethod = request.method()

        do {
            try decorateRequest(&urlRequest, handlerRequest: request)
        } catch let error {
            completion(nil, [:], error)
            return
        }

        HTTPHandler.setVisibleActivitiIndicator(visible: true)

        let task = self.urlSession.dataTask(with: urlRequest) { [weak self] (data, pResponse, error) in
            HTTPHandler.setVisibleActivitiIndicator(visible: false)

            guard let `self` = self else {
                return
            }

            guard let response = pResponse as? HTTPURLResponse else {

                if let error = error {
                    completion(nil, [:], error)
                } else {
                    let responseInfo = pResponse.debugDescription
                    completion(nil, [:], HttpHandlerError.NotHttpResponse(message: responseInfo))
                }

                return
            }

            self.handleResponse(error,
                                response,
                                data,
                                decoder,
                                completion: completion)

        }

        task.resume()
    }


    func run<T>(request: IHTTPHandlerRequest, completion: @escaping (T?, [AnyHashable: Any], Error?) -> Void) {

        guard let url = URL(string: self.baseURL + request.endPoint()) else { return }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)

        urlRequest.httpMethod = request.method()

        do {
            try decorateRequest(&urlRequest, handlerRequest: request)
        } catch let error {
            completion(nil, [:], error)
            return
        }

        HTTPHandler.setVisibleActivitiIndicator(visible: true)

        let task = self.urlSession.dataTask(with: urlRequest) { [weak self] (data, pResponse, error) in
            HTTPHandler.setVisibleActivitiIndicator(visible: false)

            guard let `self` = self else {
                return
            }

            guard let response = pResponse as? HTTPURLResponse else {

                if let error = error {
                    completion(nil, [:], error)
                } else {
                    let responseInfo = pResponse.debugDescription
                    completion(nil, [:], HttpHandlerError.NotHttpResponse(message: responseInfo))
                }

                return
            }

            self.handleResponse(error, response, data, completion: completion)

        }

        task.resume()
    }

    public func make(request: IHTTPHandlerRequest, completion: @escaping ([AnyHashable: Any]?, [AnyHashable: Any], Error?) -> Void) {
        self.run(request: request, completion: completion)
    }

    public func make<T>(request: IHTTPHandlerRequest, completion: @escaping (T?, Error?) -> Void) {
        self.run(request: request) { (result, headers, error) in
            completion(result, error)
        }
    }

    public func makeDecodable<T:Decodable>(request: IHTTPHandlerRequest, decoder: IHTTPHandlerResponseDecoder, completion: @escaping (Result<T>) -> Void) {

        self.run(request: request, decoder: decoder) { (result: T?, headers: [AnyHashable: Any], error: Error?) in

            if let error = error {
                completion(Result.failure(error))
                return
            }
            guard let result = result else {
                completion(Result.failure(HttpHandlerError.NoDataFromServer))
                return
            }

            completion(Result.success(result))
        }

    }

    public func makeDecodable<T:Decodable>(request: IHTTPHandlerRequest, completion: @escaping (Result<T>) -> Void) {

        let decoder = JSONResponseDecoder()

        self.run(request: request, decoder: decoder) { (result: T?, headers: [AnyHashable: Any], error: Error?) in

            if let error = error {
                completion(Result.failure(error))
                return
            }
            guard let result = result else {
                completion(Result.failure(HttpHandlerError.NoDataFromServer))
                return
            }

            completion(Result.success(result))
        }

    }
}
