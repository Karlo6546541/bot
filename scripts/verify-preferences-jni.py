"""Check the exact JNI descriptor used by shared_preferences in a release APK."""
import pathlib
import re
import sys

code = pathlib.Path(sys.argv[1]).read_text()
expected = "getAll(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
if expected not in re.sub(r"\s+", "", code):
    raise SystemExit("Release APK lost the SharedPreferences getAll JNI signature")
print("Release SharedPreferences getAll JNI signature preserved")
