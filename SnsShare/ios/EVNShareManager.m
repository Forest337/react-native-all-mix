//
//  EVNShareManager.m
//  EVNShare
//
//  Created by Evan Xiao on 2019/9/11.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import "EVNShareManager.h"
#import <UIKit/UIKit.h>
#import "SDWebImage.h"
#import "EVNWXManager.h"
#import "EVNWeiboManager.h"

@interface EVNShareManager()

@property (atomic, strong) NSMutableArray<UIImageView *> *downloaders;
@property (nonatomic, copy) void(^commpletion)(NSString *code,NSError *error);

@end

@implementation EVNShareManager

/**
 *  分享引擎
 *
 *  @return 唯一实例
 */
+ (instancetype)defaultManager {
  static EVNShareManager *manager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    manager = [[EVNShareManager alloc] init];
  });
  return manager;
}

- (instancetype)init {
  self = [super init];
  
  if (self) {
    self.downloaders = [NSMutableArray array];
  }
  
  return self;
}

- (void)share:(EVNShareModel *)shareModel block:(void(^)(NSString *code, NSError *error))commpletion
{
  if (shareModel.type == EVNSnsShareWeChatMini) {
//    [self shareMini:shareModel block:commpletion];
  } else if (shareModel.type == EVNSnsShareWeChatSession || shareModel.type == EVNSnsShareWeChatTimeline) {
    [self shareWX:shareModel block:commpletion];
  } else  if (shareModel.type == EVNSnsShareWeibo) {
    [self shareWeibo:shareModel block:commpletion];
  } else if (shareModel.type == EVNSnsShareQQSession) {
    [self shareQQ:shareModel block:commpletion];
  }
}

- (void)shareWeibo:(EVNShareModel *)shareModel block:(void(^)(NSString *code,NSError *error))commpletion {
  self.commpletion = commpletion;
  if (shareModel.thumb && ![@"" isEqualToString:shareModel.thumb]) {
    UIImageView *downloader = [[UIImageView alloc] init];
    [self.downloaders addObject:downloader];
    [downloader sd_setImageWithURL:[NSURL URLWithString:shareModel.thumb] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
      if (error == nil && image != nil) {
        WBMessageObject *message = [WBMessageObject message];
        message.text = [NSString stringWithFormat:@"%@ %@", shareModel.title, shareModel.webPageUrl];
        WBImageObject *imageObject = [WBImageObject object];
        imageObject.imageData = UIImagePNGRepresentation(image);
        
        message.imageObject = imageObject;
        
        WBSendMessageToWeiboRequest *wbRequest = [WBSendMessageToWeiboRequest requestWithMessage:message];
        BOOL success = [[EVNWeiboManager defaultManager] sendRequest:wbRequest];
        if (!success) {
          commpletion(@"-3", [NSError errorWithDomain:@"snsShare" code:-3 userInfo:@{NSLocalizedDescriptionKey : @"check image size or other params"}]);
          self.commpletion = nil;
        }
      } else {
        commpletion([NSString stringWithFormat:@"%ld", (long)error.code], error);
      }
      
      [self.downloaders removeObject:downloader];
    }];
  }
}

- (void)shareQQ:(EVNShareModel *)shareModel block:(void(^)(NSString *code,NSError *error))commpletion {
  self.commpletion = commpletion;
  if (shareModel.thumb && ![@"" isEqualToString:shareModel.thumb]) {
    UIImageView *downloader = [[UIImageView alloc] init];
    [self.downloaders addObject:downloader];
    
    [downloader sd_setImageWithURL:[NSURL URLWithString:shareModel.thumb] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
      if (error == nil && image != nil) {
        QQApiURLObject *obj = [[QQApiURLObject alloc] initWithURL:[NSURL URLWithString:shareModel.webPageUrl] title:shareModel.title description:shareModel.desc previewImageData:UIImagePNGRepresentation(image) targetContentType:QQApiURLTargetTypeNews];
        
        SendMessageToQQReq *req = [SendMessageToQQReq reqWithContent:obj];
        
        //将内容分享到qq
        [[EVNQQManager defaultManager] sendReq:req];
      } else {
        commpletion([NSString stringWithFormat:@"%ld", (long)error.code], error);
      }
      
      [self.downloaders removeObject:downloader];
    }];
  }
  
}

- (void)shareWX:(EVNShareModel *)shareModel block:(void(^)(NSString *code,NSError *error))commpletion
{
  self.commpletion = commpletion;
  if (shareModel.thumb && ![@"" isEqualToString:shareModel.thumb]) {
    UIImageView *downloader = [[UIImageView alloc] init];
    [self.downloaders addObject:downloader];

    [downloader sd_setImageWithURL:[NSURL URLWithString:shareModel.thumb] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
      if (error == nil && image != nil) {
        SendMessageToWXReq *req = [[SendMessageToWXReq alloc] init];
        req.scene = shareModel.type == EVNSnsShareWeChatSession ? WXSceneSession : WXSceneTimeline;

        WXMediaMessage *message = [WXMediaMessage message];

        message.title = shareModel.title;
        message.description = shareModel.desc;

        WXWebpageObject *ext = [WXWebpageObject object];
        ext.webpageUrl = shareModel.webPageUrl;
        message.mediaObject = ext;
        [message setThumbImage:image];

        req.message = message;

        [[EVNWXManager defaultManager] sendReq:req completion:^(BOOL success) {
          if (!success) {
            commpletion(@"-3", [NSError errorWithDomain:@"snsShare" code:-3 userInfo:@{NSLocalizedDescriptionKey : @"check image size or other params"}]);
            self.commpletion = nil;
          }
        }];
      } else {
        commpletion([NSString stringWithFormat:@"%ld", (long)error.code], error);
      }
      
      [self.downloaders removeObject:downloader];
    }];
  }
}

#pragma wechat delegate
- (void)onResp:(BaseResp *)resp {
  if (!self.commpletion) {
    return;
  }
  
  if ([resp isKindOfClass:[SendMessageToWXResp class]]) {
    NSString *code = [NSString stringWithFormat:@"%@", @(resp.errCode)];
    if (resp.errCode == 0) {
      self.commpletion(@"0", nil);
    } else {
      self.commpletion(code, [NSError errorWithDomain:@"share" code:resp.errCode userInfo:nil]);;
    }
    
    self.commpletion = nil;
  }
}

#pragma qq delegate
- (void)onQQResp:(QQBaseResp *)resp {
  if (!self.commpletion) {
    return;
  }
  
  if ([resp isKindOfClass:[SendMessageToQQResp class]]) {
    if (!resp.errorDescription) {
      self.commpletion(@"0", nil);
    } else {
      self.commpletion(nil, [NSError errorWithDomain:@"share" code:-10 userInfo:nil]);;
    }
  }
  
  self.commpletion = nil;
}

#pragma mark - SinaWeiboRequest Delegate
- (void)didReceiveWeiboResponse:(WBBaseResponse *)response {
  if ([response isKindOfClass:WBSendMessageToWeiboResponse.class]) {
    NSString *code = [NSString stringWithFormat:@"%@", @(response.statusCode)];
    if (response.statusCode == WeiboSDKResponseStatusCodeSuccess) {
      self.commpletion(@"0", nil);
    } else {
      self.commpletion(code, [NSError errorWithDomain:@"share" code:response.statusCode userInfo:nil]);
    }
    
    self.commpletion = nil;
  }
}

- (void)didReceiveWeiboRequest:(WBBaseRequest *)request {
  
}

@end
