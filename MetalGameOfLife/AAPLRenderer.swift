//
//  AAPLRenderer.swift
//  MetalGameOfLife
//
//  Created by nagatadaisuke on 2017/09/17.
//  Copyright © 2017年 nagatadaisuke. All rights reserved.
//

import UIKit
import MetalKit

var kTextureCount = 3;
var kInitialAliveProbability = 0.1;
var kCellValueAlive = 0;
var kCellValueDead = 255;
var kMaxInflightBuffers = 3;

class AAPLRenderer:NSObject,MTKViewDelegate {
    
    var mtkView : MTKView!
    var device : MTLDevice!
    var commandQueue : MTLCommandQueue!
    var library : MTLLibrary!
    var renderPipelineState : MTLRenderPipelineState!
    var simulationPipelineState : MTLComputePipelineState!
    var activationPipelineState : MTLComputePipelineState!
    var samplerState : MTLSamplerState!
    var textureQueue : Array<MTLTexture?> = []
    var currentGameStateTexture : MTLTexture!
    var vetexBuffer : MTLBuffer!
    var colorMap : MTLTexture!
    var gridSize : MTLSize!
    var activationPoints : Array<NSValue?> = []
    var inflightSemaphore = DispatchSemaphore(value: 3)
    var nextResizeTimestamp = Date()
    var screenAnimation = Int()
    var pointSet = CGPoint()
    
    func instanceWithView(view:MTKView)->Self
    {
        guard view.device != nil else {
            return self
        }
        
        mtkView = view
        mtkView.delegate = self
        device = mtkView.device
        library = device.makeDefaultLibrary()
        commandQueue = device.makeCommandQueue()
        
        textureQueue.reserveCapacity(kTextureCount)
        
        self.buildRenderResources()
        self.buildRenderPipeline()
        self.buildComputePipelines()
        self.reshapeWithDrawableSize(drawableSize:mtkView.drawableSize)
        
        return self
    }
    
    func cGImageForImageNamed(imageName:String)->CGImage
    {
        let image = UIImage(named: imageName)
        return (image?.cgImage)!
    }

    func buildRenderResources()
    {
        // Use MTKTextureLoader to load a texture we will use to colorize the simulation
        let textureLoader  = MTKTextureLoader.init(device: device)
        let colorMapCGImage = self.cGImageForImageNamed(imageName: "sora")
        
        do{
            colorMap = try textureLoader.newTexture(cgImage: colorMapCGImage, options: [:])
            
        }catch{}

        colorMap.label = "Color Map"
        var controlPointsBufferOptions = MTLResourceOptions()
        controlPointsBufferOptions = .storageModeShared

        let vertexData :  Array<Float> =  {
            [
               -1,  1, 0, 0,
               -1, -1, 0, 1,
                1, -1, 1, 1,
                1, -1, 1, 1,
                1,  1, 1, 0,
               -1,  1, 0, 0,
               
            ]
        }()
        
        // Full screen animation from 88
        vetexBuffer = device.makeBuffer(bytes: vertexData,
                                        length: MemoryLayout.size(ofValue: vertexData)*screenAnimation,
                                        options: controlPointsBufferOptions)

        vetexBuffer.label = "Fullscreen Quad Vertices"
    }
    
    func buildRenderPipeline()
    {

        let vertexProgram = library.makeFunction(name: "lighting_vertex")
        let fragmentProgram = library.makeFunction(name: "lighting_fragment")
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float2
        vertexDescriptor.attributes[1].offset = 2*MemoryLayout.size(ofValue: Float())
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].format = MTLVertexFormat.float2
        vertexDescriptor.layouts[0].stride =  4*MemoryLayout.size(ofValue:  Float())
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "Fullscreen Quad Pipeline"
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.mtkView.colorPixelFormat
        
        do{
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
            
        }catch{}
    }
    
    func buildComputePipelines()
    {
        commandQueue = device.makeCommandQueue()
        
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = library.makeFunction(name: "game_of_life")
        descriptor.label = "Game of Life"
        do{
            simulationPipelineState = try device.makeComputePipelineState(descriptor: descriptor,
                                                                          options: MTLPipelineOption.bufferTypeInfo,
                                                                          reflection: nil)
        }catch{}
        
        descriptor.computeFunction = library.makeFunction(name: "activate_random_neighbors")
        descriptor.label = "Activate Random Neighbors"
        do{
            activationPipelineState = try device.makeComputePipelineState(descriptor: descriptor,
                                                                          options: MTLPipelineOption.bufferTypeInfo,
                                                                          reflection: nil)
        }catch{}
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = MTLSamplerAddressMode.clampToZero
        samplerDescriptor.tAddressMode = MTLSamplerAddressMode.clampToZero
        samplerDescriptor.minFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.magFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
    }
    
    func reshapeWithDrawableSize(drawableSize:CGSize)
    {

        let scale = self.mtkView.layer.contentsScale
        let proposedGridSize = MTLSize(width: Int(drawableSize.width/scale), height: Int(drawableSize.height/scale), depth: 1)
        
        gridSize = proposedGridSize
        
        self.buildComputeResources()
        
    }
    
    func buildComputeResources()
    {
        textureQueue.removeAll()
        currentGameStateTexture = nil

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.r8Uint,
                                                                  width: gridSize.width,
                                                                  height: gridSize.height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead,.shaderWrite]
        
        for _ in 0...kTextureCount-1{
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = "Game State"
            textureQueue.append(texture)
     
        }
        
        let randomGrid  = [(gridSize.width * gridSize.height)]
        
        let currentReadTexture = textureQueue.last
        currentReadTexture??.replace(region: MTLRegionMake2D(0, 0, 1, gridSize.height),
                                     mipmapLevel : 0,
                                     withBytes: randomGrid,
                                     bytesPerRow: gridSize.width)

    }
    
    //MARK: - Interactivity
    func activateRandomCellsInNeighborhoodOfCell(cell:CGPoint)
    {
        pointSet = cell
        self.activationPoints.append(NSValue(cgPoint: cell))
    }
    
    //MARK: - Render and Compute Encoding
    func encodeComputeWorkInBuffer(commandBuffer:MTLCommandBuffer)
    {

        let readTexture = self.textureQueue.last
        let writeTexture = self.textureQueue.first

        let commandEncoder = commandBuffer.makeComputeCommandEncoder()

        //Returns the specified size of an object, such as a texture or threadgroup.
        let threadsPerThreadgroup = MTLSizeMake(3, 3, 1)
        let threadgroupCount = MTLSizeMake((self.gridSize.width/threadsPerThreadgroup.width), (self.gridSize.height/threadsPerThreadgroup.height), 1)

        commandEncoder?.setComputePipelineState(self.simulationPipelineState)
        commandEncoder?.setTexture(readTexture!, index: 0)
        commandEncoder?.setTexture(writeTexture!, index: 1)
        
        commandEncoder?.setSamplerState(self.samplerState, index: 0)
        commandEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)

        if self.activationPoints.count > 0 && Int(self.pointSet.x) != 0 {
   
            let byteCount = self.activationPoints.count * 2 * MemoryLayout.size(ofValue: 1)
            var cellPositions  = [(byteCount,byteCount)]
            
                        for (_, byteCount) in self.activationPoints.enumerated() {
                
                                var point = CGPoint()
                                byteCount?.getValue(&point)
                
                            cellPositions = [(Int(point.x),Int(point.y))]
            
                        }
            
            let threadsPerThreadgroup = MTLSize(width: self.activationPoints.count,height: 1,depth: 1)
            let threadgroupCount = MTLSize(width:Int(self.pointSet.x),height: Int(self.pointSet.y),depth: 1)

            commandEncoder?.setComputePipelineState(self.activationPipelineState)
            commandEncoder?.setTexture(writeTexture!, index: 0)
            commandEncoder?.setBytes(cellPositions, length: byteCount, index: 0)

            commandEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)

            self.activationPoints.removeAll()

        }
        
        commandEncoder?.endEncoding()

        self.currentGameStateTexture = self.textureQueue.first!!
        self.textureQueue.remove(at: 0)
        self.textureQueue.append(self.currentGameStateTexture)
    }
    
    func encodeRenderWorkInBuffer(commandBuffer:MTLCommandBuffer)
    {
        let renderPassDescriptor = self.mtkView.currentRenderPassDescriptor
        
        if renderPassDescriptor != nil {
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
            
            renderEncoder?.setRenderPipelineState(self.renderPipelineState)
            renderEncoder?.setVertexBuffer(vetexBuffer, offset: 0, index: 0)
            renderEncoder?.setFragmentTexture(self.currentGameStateTexture, index: 0)
            renderEncoder?.setFragmentTexture(self.colorMap, index: 1)
            
            renderEncoder?.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
       
            renderEncoder?.endEncoding()

            commandBuffer.present(self.mtkView.currentDrawable!)
        }
        
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    {
        let resizeHysteresis : TimeInterval = 0.200
        self.nextResizeTimestamp = Date.init(timeIntervalSinceNow: resizeHysteresis)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + resizeHysteresis) {
            if self.nextResizeTimestamp.timeIntervalSinceNow <= 0 {
                self.reshapeWithDrawableSize(drawableSize: self.mtkView.drawableSize)
            }
        }
    }

    func draw(in view: MTKView)
    {
        self.inflightSemaphore.wait()
        let commandBuffer = self.commandQueue.makeCommandBuffer()
        
        commandBuffer!.addCompletedHandler {  (_) in
            self.inflightSemaphore.signal()
        }
        
        self.encodeComputeWorkInBuffer(commandBuffer: commandBuffer!)
        self.encodeRenderWorkInBuffer(commandBuffer: commandBuffer!)
        
        commandBuffer?.commit()

    }
}
