//
//  ViewController.swift
//  MetalGameOfLife
//
//  Created by nagatadaisuke on 2017/09/17.
//  Copyright © 2017年 nagatadaisuke. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    
    var metalView: MTKView!
    var slider = UISlider()
    var aAPLRenderer = AAPLRenderer()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.metalView = MTKView()
        self.view.addSubview(metalView)
        
        self.swipeMethod()
        self.view.addSubview(slider)
        slider.frame = CGRect(x:0,y:UIScreen.main.bounds.height-100,width:UIScreen.main.bounds.width,height:44)
        slider.minimumValue = 4
        slider.maximumValue = 11
        slider.addTarget(self, action: #selector(sliderHorizon(_:)), for: UIControl.Event.touchUpInside)
        
    }
    
    private func setupView()
    {
        
        self.metalView.device = MTLCreateSystemDefaultDevice()
        self.metalView.colorPixelFormat = MTLPixelFormat.bgra8Unorm
        self.metalView.clearColor =  MTLClearColorMake(0, 0, 0, 1)
        self.metalView.frame = self.view.frame
        self.metalView.isUserInteractionEnabled = true
        
    }
    
    private func swipeMethod()
    {
        let directions: [UISwipeGestureRecognizer.Direction] = [.right, .left, .up, .down]
        for direction in directions {
            let gesture = UISwipeGestureRecognizer(target: self,
                                                   action:#selector(handleSwipe(sender:)))
            
            gesture.direction = direction
            self.view.addGestureRecognizer(gesture)
        }
    }
    
    func locationInGridForLocationInView(point:CGPoint)->CGPoint
    {
        
        guard self.aAPLRenderer.gridSize != nil else {
            return CGPoint(x:0,y:0)
        }
        
        let viewSize = self.view.frame.size
        let normalizedWidth = point.x / viewSize.width
        let normalizedHeight = point.y / viewSize.height
        
        let gridX = round(normalizedWidth * CGFloat(self.aAPLRenderer.gridSize.width))
        let gridY = round(normalizedHeight * CGFloat(self.aAPLRenderer.gridSize.height))
        
        return CGPoint(x:gridX,y:gridY)
    }
    
    func activateRandomCellsForPoint(point:CGPoint)
    {
        let gridLocation =  self.locationInGridForLocationInView(point: point)
        self.aAPLRenderer.activateRandomCellsInNeighborhoodOfCell(cell: gridLocation)
    }
    
    @objc func handleSwipe(sender: UISwipeGestureRecognizer)
    {
        
        guard self.metalView != nil else {
            return
        }
        
        _ = self.aAPLRenderer.instanceWithView(view: self.metalView)
        
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        
        for touch : UITouch in touches {
            let location = touch.location(in: self.view)
            self.activateRandomCellsForPoint(point: location)
        }
    }
    
    @objc func sliderHorizon(_ sender: UISlider)
    {

        self.aAPLRenderer.screenAnimation =  Int(sender.value)
        self.setupView()
        _ = self.aAPLRenderer.instanceWithView(view: self.metalView)
        
    }
}
