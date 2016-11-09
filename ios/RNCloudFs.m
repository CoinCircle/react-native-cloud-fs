
#import "RNCloudFs.h"
#import <UIKit/UIKit.h>
#import "RCTBridgeModule.h"
#import "RCTEventDispatcher.h"
#import "RCTUtils.h"

@implementation RNCloudFs

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(copyToCloud:(NSString *)sourceUri :(NSString *)destinationPath :(NSString *)mimeType
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    // mimeType is ignored for iOS

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSString *tempFile;

        if ([fileManager fileExistsAtPath:sourceUri isDirectory:nil]) {
            NSURL *sourceURL = [NSURL fileURLWithPath:sourceUri];

            // todo: figure out how to *copy* to icloud drive
            // ...setUbiquitous will move the file instead of copying it, so as a work around lets copy it to a tmp file first
            NSString *filename = [sourceUri lastPathComponent];
            tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
            NSError *error;
            [fileManager copyItemAtPath:sourceURL toPath:tempFile error:&error];
            NSLog(@"Moving file %@ to %@", tempFile, destinationPath);

        } else if ([sourceUri hasPrefix:@"file:/"]) {
            NSError *error;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^file:/+" options:NSRegularExpressionCaseInsensitive error:&error];
            NSString *modifiedSourceUri = [regex stringByReplacingMatchesInString:sourceUri options:0 range:NSMakeRange(0, [sourceUri length]) withTemplate:@"/"];

            if ([fileManager fileExistsAtPath:modifiedSourceUri isDirectory:nil]) {
                NSURL *sourceURL = [NSURL fileURLWithPath:modifiedSourceUri];

                // todo: figure out how to *copy* to icloud drive
                // ...setUbiquitous will move the file instead of copying it, so as a work around lets copy it to a tmp file first
                NSString *filename = [sourceUri lastPathComponent];
                tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
                NSError *error;
                [fileManager copyItemAtPath:sourceURL toPath:tempFile error:&error];
                NSLog(@"Moving file %@ to %@", tempFile, destinationPath);
            } else {
                NSLog(@"source file does not exist %@", sourceUri);
                return reject(@"ENOENT", [NSString stringWithFormat:@"ENOENT: no such file or directory, open '%@'", sourceUri], nil);
            }
        } else {
            NSURL *url = [NSURL URLWithString:sourceUri];
            NSData *urlData = [NSData dataWithContentsOfURL:url];
            if (urlData) {
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];

                NSString *filename = [sourceUri lastPathComponent];
                tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
                [urlData writeToFile:tempFile atomically:YES];
            } else {
                NSLog(@"source file does not exist %@", sourceUri);
                return reject(@"ENOENT", [NSString stringWithFormat:@"ENOENT: no such file or directory, open '%@'", sourceUri], nil);
            }
        }

        [self rootDirectoryForICloud:^(NSURL *ubiquityURL) {
            if (ubiquityURL) {
                NSURL* targetFile = [ubiquityURL URLByAppendingPathComponent:destinationPath];
                NSLog(@"Target file: %@", targetFile.path);

                NSURL *dir = [targetFile URLByDeletingLastPathComponent];
                if (![fileManager fileExistsAtPath:dir.path isDirectory:nil]) {
                    [fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
                }

                NSError *error;
                if ([fileManager setUbiquitous:YES itemAtURL:[NSURL fileURLWithPath:tempFile] destinationURL:targetFile error:&error]) {
                    return resolve(@{@"path": targetFile.absoluteString});
                } else {
                    NSLog(@"Error occurred: %@", error);
                    NSString *codeWithDomain = [NSString stringWithFormat:@"E%@%zd", error.domain.uppercaseString, error.code];
                    return reject(codeWithDomain, error.localizedDescription, error);
                }
            } else {
                NSLog(@"Could not retrieve a ubiquityURL");
                return reject(@"ENOENT", [NSString stringWithFormat:@"ENOENT: could not copy to iCloud drive '%@'", sourceUri.absolutePath], nil);
            }
        }];
    });
}

- (void)rootDirectoryForICloud:(void (^)(NSURL *))completionHandler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL *rootDirectory = [[fileManager URLForUbiquityContainerIdentifier:nil] URLByAppendingPathComponent:@"Documents"];
        
        if (rootDirectory) {
            if (![fileManager fileExistsAtPath:rootDirectory.path isDirectory:nil]) {
                NSLog(@"Creating documents directory: %@", rootDirectory.path);
                [fileManager createDirectoryAtURL:rootDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(rootDirectory);
        });
    });
}

- (NSURL *)localPathForResource:(NSString *)resource ofType:(NSString *)type {
    NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *resourcePath = [[documentsDirectory stringByAppendingPathComponent:resource] stringByAppendingPathExtension:type];
    return [NSURL fileURLWithPath:resourcePath];
}

@end
