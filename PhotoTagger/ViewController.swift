/*
* Copyright (c) 2015 Razeware LLC
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*/

import UIKit
import Alamofire

class ViewController: UIViewController {
  
  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
  
  // MARK: - Properties
  fileprivate var tags: [String]?
  fileprivate var colors: [PhotoColor]?

  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()

    if !UIImagePickerController.isSourceTypeAvailable(.camera) {
      takePictureButton.setTitle("Select Photo", for: UIControlState())
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    imageView.image = nil
  }

  // MARK: - Navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

    if segue.identifier == "ShowResults" {
      guard let controller = segue.destination as? TagsColorsViewController else {
        fatalError("Storyboard mis-configuration. Controller is not of expected type TagsColorsViewController")
      }

      controller.tags = tags
      controller.colors = colors
    }
  }

  // MARK: - IBActions
  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = UIImagePickerControllerSourceType.camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }

    present(picker, animated: true, completion: nil)
  }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController : UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
    guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true, completion: nil)
      return
    }
    
    imageView.image = image
    
    // 1
    // hide upload button, show progress view and activity view
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()
    
    uploadImage(
      image: image,
      progress: { [unowned self] percent in
        // 2
        // while file upload, you call the progress handler with updated percent
        // changes the amount of progress bar showing
        self.progressView.setProgress(percent, animated: true)
      }) { [unowned self] tags, colors in
        // 3
        // completion handler executes when the upload finishes
        // sets the state of the controls back to initial
        self.takePictureButton.isHidden = false
        self.progressView.isHidden = true
        self.activityIndicatorView.stopAnimating()
        
        self.tags = tags
        self.colors = colors
        
        // 4
        // go to results screen and show the results
        self.performSegue(withIdentifier: "ShowResults", sender: self)
    }
    
      
    dismiss(animated: true, completion: nil)
  }
}

// Networking calls
extension ViewController {
  // convert UIImage to a JPEG
  func uploadImage(image: UIImage, progress: (_ percent: Float) -> Void,
    completion: @escaping (_ tags: [String], _ colors: [PhotoColor]) -> Void) {
    guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
      print("Could not get JPEG representation of UIImage")
      return
    }
    
    Alamofire.upload(multipartFormData: { multipartFormData in
      multipartFormData.append(imageData, withName: "imagefile", fileName: "image.jpg", mimeType: "image/jpeg")
    }, with: ImaggaRouter.Content) { encodingResult in
      switch encodingResult {
      // calls the alamofire upload function
      case .success(let upload, _, _):
        upload.uploadProgress(queue: DispatchQueue.main) { progress in
          print("upload progress: \(progress.fractionCompleted)")
          self.progressView.progress = Float(progress.fractionCompleted)
        }
        upload.validate()
        upload.responseJSON { response in
          // 1
          // check if response was successful
          guard response.result.isSuccess else {
            // print error if not and call the completion handler
            print("Error while uploading file: \(response.result.error)")
            completion([String](), [PhotoColor]())
            return
          }
          // 2
          // check each portion of the response, verifiying the expected type is the actual type received
          // if firstFileID cant be resolved print error message and call completion handler
          guard let responseJSON = response.result.value as? [String: AnyObject],
            let uploadedFiles = responseJSON["uploaded"] as? [AnyObject],
            let firstFile = uploadedFiles.first as? [String: AnyObject],
            let firstFileID = firstFile["id"] as? String else {
              // if firstFileID can't be resolved, print out an error message and call the completion handler
              print("Invalid information received from service")
              completion([String](), [PhotoColor]())
              return
            }
          
          print("Content uploaded with ID: \(firstFileID)")
          // 3
          // call the completion handler to update the UI
          
          // sends the tags to the completion handler
          self.downloadTags(contentID: firstFileID, completion: { tags in
            self.downloadColors(contentID: firstFileID, completion: { colors in
              completion(tags, colors)
            })
          })
        }
      case .failure(let encodingError):
        print(encodingError)
      }
    }
  }
  
  func downloadTags(contentID: String, completion: @escaping ([String]) -> Void) {
    // send a HTTP GET request against tagging endpoint
    // sending the URL parameter content with the ID you received after upload
    Alamofire.request(ImaggaRouter.Tags(contentID))
    .responseJSON { response in
      
      // 1
      // check if response was successful; if not, print error and call completion handler
      guard response.result.isSuccess else {
        print("Error while fetching tags: \(response.result.error)")
        completion([String]())
        return
      }
      
      // 2
      // check each portion of the response, verifiying the expected type is the actual type received
      // if tagsAndConfidences cant be resolved print error meesage and call completion handler
      guard let responseJSON = response.result.value as? [String: AnyObject],
        let results = responseJSON["results"] as? [AnyObject],
        let firstResult = results.first,
        let tagsAndConfidences = firstResult["tags"] as? [[String: AnyObject]] else {
        print("Invalid tag information received from service")
        completion([String]())
        return
      }
      
      // 3
      // iterate over each dictionary object in tagsAndConfidences array, retrieving the value associated with the tag key
      let tags = tagsAndConfidences.flatMap({ dict in
        return dict ["tag"] as? String
      })
      
      // 4
      // call the completion handler passing the tags reveived from the service
      completion(tags)
    }
  }
  
  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]) -> Void) {
    Alamofire.request(ImaggaRouter.Colors(contentID))
    .responseJSON { response in
      // 1
      // check if response was successful; if not, print error and call completion handler
      guard response.result.isSuccess else {
        print("Error while fetching colors: \(response.result.error)")
        completion([PhotoColor]())
        return
      }
      
      // 2
      // check each portion of the response, verifiying the expected type is the actual type received
      // if imageColors cant be resolved print error meesage and call completion handler
      guard let responseJSON = response.result.value as? [String: AnyObject],
        let results = responseJSON["results"] as? [AnyObject],
        let firstResult = results.first as? [String: AnyObject],
        let info = firstResult["info"] as? [String: AnyObject],
        let imageColors = info["image_colors"] as? [[String: AnyObject]] else {
          print("Invalid color information reveived from service")
          completion([PhotoColor]())
          return
      }
      
      // 3
      // Using flatMap, iterate over the returned imageColors, transforming the data into PhotoColor objects
      // which pairs colors in the RGB format with the color name as a string
      // Note: Tthe provided closure allows returning nil values since flatMap will simply ignore them
      let photoColors = imageColors.flatMap({ (dict) -> PhotoColor? in
        guard let r = dict["r"] as? String,
          let g = dict["g"] as? String,
          let b = dict["b"] as? String,
          let closestPaletteColor = dict["closest_palette_color"] as? String else {
            return nil
        }
        return PhotoColor(red: Int(r),
                          green: Int(g),
                          blue: Int(b),
                          colorName: closestPaletteColor)
      })
      
      // 4
      // call completion handler, passing in the photoColors from the service
      completion(photoColors)
    }
  }
}
