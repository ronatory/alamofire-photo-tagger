//
//  ImaggaRouter.swift
//  PhotoTagger
//
//  Created by ronatory on 16.10.16.
//  Copyright © 2016 ronatory. All rights reserved.
//

import Foundation
import Alamofire

public enum ImaggaRouter: URLRequestConvertible {
  static let baseURLPath = "http://api.imagga.com/v1"
  //TODO: Replace xxx with your auth token found at https://imagga.com/profile/dashboard
  static let authenticationToken = "Basic xxx"
  
  case Content
  case Tags(String)
  case Colors(String)

  public func asURLRequest() throws -> URLRequest {
    let result: (path: String, method: Alamofire.HTTPMethod, parameters: [String: AnyObject]) = {
      switch self {
      case .Content:
        return ("/content", .post, [String: AnyObject]())
      case .Tags(let contentID):
        let params = ["content": contentID]
        return ("/tagging", .get, params as [String : AnyObject])
      case .Colors(let contentID):
        let params = ["content": contentID, "extract_object_colors" : NSNumber(value: 0)] as [String : Any]
        return ("/colors", .get, params as [String : AnyObject])
      }
    }()
    let url = try ImaggaRouter.baseURLPath.asURL()
    var urlRequest = URLRequest(url: url.appendingPathComponent(result.path))
    urlRequest.httpMethod = result.method.rawValue
    urlRequest.setValue(ImaggaRouter.authenticationToken, forHTTPHeaderField: "Authorization")
    urlRequest.timeoutInterval = TimeInterval(10 * 1000)
    
    return try URLEncoding.default.encode(urlRequest, with: result.parameters)
  }
}
