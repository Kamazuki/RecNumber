//
//  ViewController.m
//  RecNumber
//
//  Created by Kamazuki on 2020/5/14.
//  Copyright © 2020 Tencent. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreML/CoreML.h>

@interface UIImage (Extend)

- (UIImage*) grayscaleImage;
- (UIImage*) scaledToSize:(CGSize)newSize;
- (UIImage*) crop:(CGRect)rect;

@end

@implementation UIImage (Extend)

- (UIImage*) grayscaleImage
{
    return [self imageWithCIFilter:@"CIPhotoEffectMono"];
}

- (UIImage*) imageWithCIFilter:(NSString*) filterName
{
    CIImage* unfiltered = [CIImage imageWithCGImage:self.CGImage];
    CIFilter* filter = [CIFilter filterWithName:filterName];
    [filter setValue:unfiltered forKey:kCIInputImageKey];
    CIImage* filtered = [filter outputImage];
    CIContext* context = [CIContext contextWithOptions:nil];
    CGImageRef cgimage = [context createCGImage:filtered fromRect:CGRectMake(0, 0, self.size.width * self.scale, self.size.height * self.scale)];
    UIImage *image = [[UIImage alloc] initWithCGImage:cgimage scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(cgimage);
    return image;
}

- (UIImage*) scaledToSize:(CGSize) newSize
{
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 1);
    [self drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (UIImage*) crop:(CGRect) rect
{
    UIGraphicsBeginImageContextWithOptions(rect.size, false, self.scale);
    [self drawAtPoint:CGPointMake(-rect.origin.x, -rect.origin.y)];
    UIImage* result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

@end

@interface MyProvider : NSObject
<
    MLFeatureProvider
>

@property MLFeatureValue* m_value;

-(id) initWithFeatureValue:(MLFeatureValue*) value;

@end

@implementation MyProvider

-(id) initWithFeatureValue:(MLFeatureValue *)value
{
    self = [super init];
    if (self) {
        self.m_value = value;
    }
    return self;
}

- (nullable MLFeatureValue *)featureValueForName:(NSString *)featureName
{
    return self.m_value;
}

-(NSSet*) featureNames
{
    NSMutableSet* set = [NSMutableSet set];
    [set addObject:@"input1"];
    return set;
}

@end

@interface ViewController ()
<
    AVCaptureVideoDataOutputSampleBufferDelegate
>

@property AVCaptureVideoPreviewLayer* previewLayer;
@property MLModel* model;
@property UIView* topBarView;
@property UIView* bottomBarView;
@property UILabel* numberLabel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self updateModel];
    [self updateDevice];
    [self updateTopBarView];
    [self updateBottomBarView];
    [self updateNumberLabel];
}

-(void) viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateTopBarView];
    [self updateBottomBarView];
    [self updateNumberLabel];
}

-(void) updateTopBarView
{
    if (self.topBarView == nil) {
        self.topBarView = [[UIView alloc] init];
        self.topBarView.backgroundColor = UIColor.grayColor;
        [self.view addSubview:self.topBarView];
    }
    
    self.topBarView.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height / 2 - self.view.frame.size.width / 2);
}

-(void) updateBottomBarView
{
    if (self.bottomBarView == nil) {
        self.bottomBarView = [[UIView alloc] init];
        self.bottomBarView.backgroundColor = UIColor.grayColor;
        [self.view addSubview:self.bottomBarView];
    }
    
    self.bottomBarView.frame = CGRectMake(0, self.view.frame.size.height -  (self.view.frame.size.height / 2 - self.view.frame.size.width / 2), self.view.frame.size.width, self.view.frame.size.height / 2 - self.view.frame.size.width / 2);
}

-(void) updateNumberLabel
{
    if (self.numberLabel == nil) {
        self.numberLabel = [[UILabel alloc] init];
        self.numberLabel.font = [UIFont boldSystemFontOfSize:32];
        self.numberLabel.textColor = UIColor.orangeColor;
        
        [self.bottomBarView addSubview:self.numberLabel];
    }
}

-(void) updateDevice
{
    //创建session
    AVCaptureSession* session = [AVCaptureSession new];
    
    //设置分辨率
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        [session setSessionPreset:AVCaptureSessionPreset640x480];
    }
    else {
        [session setSessionPreset:AVCaptureSessionPresetLow];
    }
    
    //获取摄像头device
    AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError* error = nil;
    AVCaptureDeviceInput* deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if ([session canAddInput:deviceInput]) {
        [session addInput:deviceInput];
    }
    
    //创建输出
    AVCaptureVideoDataOutput* videoDataOutput = [AVCaptureVideoDataOutput new];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    dispatch_queue_t queue = dispatch_queue_create("video_out_put_queue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:queue];
    
    if ([session canAddOutput:videoDataOutput]) {
        [session addOutput:videoDataOutput];
    }
    
    AVCaptureConnection* videoCon = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([videoCon isVideoMirroringSupported]) {
        videoCon.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [self.previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    [self.view.layer setMasksToBounds:YES];
    [self.previewLayer setFrame:self.view.layer.bounds];
    
    [self.view.layer addSublayer:self.previewLayer];
    
    [session startRunning];
}

-(void) updateModel
{
    NSError* error = nil;
    NSURL *modelUrl = [[NSBundle mainBundle] URLForResource:@"firstDemo" withExtension:@"mlmodelc"];
    self.model = [MLModel modelWithContentsOfURL:modelUrl error:&error];
    if (error == nil) {
        NSLog(@"%@", [error description]);
    }
}

+ (NSArray*) getPixelArrayFromGrayScaleImage:(UIImage*)image
{
    //存储结果
    NSMutableArray *result = [NSMutableArray array];

    CGImageRef imageRef = [image CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    
    //使用灰度图的色彩空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

    {
        NSUInteger bytesPerPixel = 1;
        NSUInteger bytesPerRow = bytesPerPixel * width;
        NSUInteger bitsPerComponent = 8;
        
        unsigned char* rawData = (unsigned char*) calloc(height * width * bytesPerPixel, sizeof(unsigned char));
        CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                        bitsPerComponent, bytesPerRow, colorSpace,
                        kCGImageAlphaNone);
        {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
            
            // Now your rawData contains the image data in the RGBA8888 pixel format.
            for (int i = 0; i < height * width; ++i)
            {
                [result addObject:[NSNumber numberWithFloat:rawData[i] / 255.0]];
            }
        }
        CGContextRelease(context);
        free(rawData);
    }
    CGColorSpaceRelease(colorSpace);
    return result;
}

+(MLMultiArray*) mlMultiArrayFromArray:(NSArray*) array imageSize:(int32_t) imageSize
{
    NSError* error = nil;
    NSMutableArray* shape = [NSMutableArray array];
    [shape addObject:[NSNumber numberWithInt:imageSize * imageSize]];
    MLMultiArray* mulArray = [[MLMultiArray alloc] initWithShape:shape dataType:MLMultiArrayDataTypeFloat32 error:&error];
    if (error != nil) {
        NSLog(@"%@", [error description]);
        return nil;
    }
    
    int32_t index = 0;
    for (NSNumber* number in array) {
        [mulArray setObject:number atIndexedSubscript:index];
        ++ index;
    }
    
    return mulArray;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    @autoreleasepool {
        
        // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
        if (self.model == nil) {
            return;
        }
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        uint32_t imageSize = 28;
        
        CIImage* ciimage = [CIImage imageWithCVImageBuffer:imageBuffer];
        UIImage* image = [UIImage imageWithCIImage:ciimage];
        UIImage* cropImage = [image crop:CGRectMake(0, image.size.height / 2 - image.size.width / 2, image.size.width, image.size.width)];
        UIImage* scaleImage = [cropImage scaledToSize:CGSizeMake(imageSize, imageSize)];
        UIImage* grayImage = [scaleImage grayscaleImage];

        NSArray* array = [ViewController getPixelArrayFromGrayScaleImage:grayImage];
        MLMultiArray* mulArray = [ViewController mlMultiArrayFromArray:array imageSize:imageSize];
        
        MLFeatureValue* mlValue = [MLFeatureValue featureValueWithMultiArray:mulArray];
        
        MyProvider* provider = [[MyProvider alloc] initWithFeatureValue:mlValue];

        NSError* error = nil;
        id<MLFeatureProvider> result = [self.model predictionFromFeatures:provider error:&error];
        
        if (error != nil) {
            NSLog(@"%@", [error description]);
            return;
        }
        
        MLFeatureValue* resultValue = [result featureValueForName:@"output1"];
        
        int maxIndex = 0;
        float currentChance = 0;
        for (int index = 0; index < 10; ++ index) {
            NSNumber* number = [resultValue.multiArrayValue objectAtIndexedSubscript:index];
            if (number.floatValue > currentChance) {
                currentChance = number.floatValue;
                maxIndex = index;
            }
        }
        
        NSLog(@"predicted number: %d", maxIndex);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.numberLabel.text = [NSString stringWithFormat:@"%d", maxIndex];
            [self.numberLabel sizeToFit];
            
            self.numberLabel.center = CGPointMake(self.bottomBarView.frame.size.width / 2, self.bottomBarView.frame.size.height / 2);
        });
    }
}

@end
