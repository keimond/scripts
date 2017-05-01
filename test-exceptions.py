#!/usr/bin/python

def divide(x, y):
  try:
    result = x / y
  except (ZeroDivisionError, TypeError), e:
    print "e:", e
  else:
    print "result is", result
  finally:
    print "executing finally clause"

print "def divide(x, y) performs the math calculation \"x / y\"\n"
print "Trying divide(2, 1)"
divide(2, 1)
print "\nTrying divide(2, 0)"
divide(2, 0)
print "\nTrying divide(\"2\", \"1\")"
divide("2", "1")


''' random error handling for a lightcloud script as another example...

    except (socket.timeout, socket.error, MemoryError, lightcloud.LightcloudOperationError, ValueError), e:
      if verbosity != 'silent':
        print e

    except:
      print "Unexpected error: ", sys.exc_info()[0]'''
