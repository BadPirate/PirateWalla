//
//  MapVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 2/5/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit
import MapKit

class MapVC : PWVC, MKMapViewDelegate {
    @IBOutlet var target : UIImageView?
    @IBOutlet var searchButton : UIBarButtonItem?
    @IBOutlet var resetButton : UIBarButtonItem?
    @IBOutlet var mapView : MKMapView?
    let itemLock = dispatch_queue_create("ItemLock", nil)
    var savedItems = [ Int : SBSavedItem ]()
    var pouchItems = [ Int : SBSavedItem ]()
    var mixReverseLookup = [ Int : SBItemType ]()
    var user : SBUser?
    let bee = sharedBee
    var zoomed = false
    var recheck = false
    var places = Set<SBPlace>()
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        alwaysShow = true
    }
    
    override func viewDidLoad() {
        reset()
        super.viewDidLoad()
    }
    
    @IBAction func reset() {
        searchButton!.enabled = false
        resetButton!.enabled = false
        recheck = true
        dispatch_sync(self.itemLock, { () -> Void in
            self.savedItems.removeAll()
            self.pouchItems.removeAll()
            self.mixReverseLookup.removeAll()
        })
        let activity = "Resetting"
        startedActivity(activity)
        ActionTVC.login(self) { (user) -> Void in
            defer { self.stoppedActivity(activity) }
            self.user = user
            ActionTVC.getSavedItems(user, watcher: self, completion: { (error, savedItems) -> Void in
                if let error = error {
                    self.errored(error)
                    return
                }
                let savedItems = savedItems!
                dispatch_sync(self.itemLock, { () -> Void in
                    self.savedItems = savedItems
                })
                ActionTVC.addMixRequirements(self, savedItems: savedItems, itemLock: self.itemLock, completion: { (error, mixReverseLookup) -> Void in
                    if let mixReverseLookup = mixReverseLookup {
                        self.mixReverseLookup = mixReverseLookup
                    }
                })
            })
            ActionTVC.getPouch(user, watcher: self, completion: { (error, pouchItems) -> Void in
                if let error = error {
                    self.errored(error)
                    return
                }
                let pouchItems = pouchItems!
                dispatch_sync(self.itemLock, { () -> Void in
                    self.pouchItems = pouchItems
                })
            })
        }
    }
    
    override func didCompleteAllActivities() {
        if !NSThread.isMainThread() {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.didCompleteAllActivities()
            })
            return
        }
        super.didCompleteAllActivities()
        searchButton!.enabled = true
        resetButton!.enabled = true
        if recheck {
            let mapView = self.mapView!
            let annotations = mapView.annotations
            mapView.removeAnnotations(annotations)
            mapView.addAnnotations(annotations)
            recheck = false
        }
    }
    
    func errored(error : NSError) {
        searchButton!.enabled = true
        resetButton!.enabled = true
        AppDelegate.handleError(error, button: "Retry", title: "Error", completion: {
            self.reset()
        })
    }
    
    @IBAction func search() {
        let searchButton = self.searchButton!, mapView = self.mapView!, target = self.target!
        searchButton.enabled = false
        
        let coordinate = mapView.convertPoint(target.center, toCoordinateFromView: target.superview)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let activity = "Searching!  ARRR!"
        startedActivity(activity)
        bee.priorityMode = true
        bee.nearby(location) { (error, places) -> Void in
            defer { self.stoppedActivity(activity) }
            if let error = error {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    searchButton.enabled = true
                })
                AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                return
            }
            let places = places!
            var maxDistance : CLLocationDistance = 0
            for place in places {
                let placeCoordinate = place.location
                let placeLocation = CLLocation(latitude: placeCoordinate.latitude, longitude: placeCoordinate.longitude)
                maxDistance = max(maxDistance,location.distanceFromLocation(placeLocation))
            }
            let circle = MKCircle(centerCoordinate: coordinate, radius: maxDistance)
            let newPlaces = Set<SBPlace>(places).subtract(self.places)
            var annotations = [MKAnnotation]()
            for place in newPlaces {
                annotations.append(PlaceAnnotation(place: place, watcher: self))
            }
            self.places.unionInPlace(newPlaces)
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                mapView.addOverlay(circle)
                searchButton.enabled = true
                mapView.setVisibleMapRect(circle.boundingMapRect, animated: true)
                if annotations.count > 0 {
                    mapView.addAnnotations(annotations)
                }
            })
        }
        bee.priorityMode = false
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? PlaceAnnotation {
            guard let items = annotation.items else {
                let hiddenView = MKAnnotationView(annotation: annotation, reuseIdentifier: "hidden")
                hiddenView.hidden = true
                return hiddenView
            }
            var placeObjects = PlaceObjects()
            ActionTVC.placeObjects(items, place: annotation.place, savedItems: savedItems, pouchItemTypes: pouchItems, mixReverseLookup: mixReverseLookup, placeObjects: &placeObjects)
            
            var n = 1
            while let type = FoundItemType(rawValue: n)
            {
                if let typeObjects = placeObjects[type], let _ = typeObjects[annotation.place] {
                    let av = MKAnnotationView(annotation: annotation, reuseIdentifier: type.name)
                    av.image = UIImage(named: type.name)
                    return av
                }
                n++
            }
            
            let hiddenView = MKAnnotationView(annotation: annotation, reuseIdentifier: "hidden")
            hiddenView.hidden = true
            return hiddenView
        }
        return nil
    }
    
    func mapView(mapView: MKMapView, didUpdateUserLocation userLocation: MKUserLocation) {
        if zoomed { return }
        zoomed = true
        mapView.setRegion(MKCoordinateRegion(center: userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)), animated: true)
    }
    
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        if let overlay = overlay as? MKCircle {
            let renderer = MKCircleRenderer(overlay: overlay)
            renderer.fillColor = UIColor(colorLiteralRed: 0, green: 0, blue: 0, alpha: 0.15)
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

class PlaceAnnotation : NSObject, MKAnnotation {
    let place : SBPlace
    var items : [SBItem]?
    init(place : SBPlace, watcher : MapVC) {
        self.place = place
        super.init()
        let activity = "Searching \(place.name)"
        watcher.startedActivity(activity)
        place.items { (error, items) -> Void in
            defer { watcher.stoppedActivity(activity) }
            if let error = error {
                print(error)
                return
            }
            if let items = items {
                self.items = items
                if NSThread.isMainThread() {
                    watcher.mapView!.removeAnnotation(self)
                    watcher.mapView!.addAnnotation(self)
                }
                else
                {
                    dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                        watcher.mapView!.removeAnnotation(self)
                        watcher.mapView!.addAnnotation(self)
                    })
                }
            }
        }
    }
    var coordinate : CLLocationCoordinate2D {
        get {
            return place.location
        }
    }
    var title : String? {
        get {
            return place.name
        }
    }
    
}
