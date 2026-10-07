"""Stage a tidy data set on the LOCAL QA server for store screenshots.
The phone stays signed in as qa_android; its chats are cleared and rebuilt."""
import contextlib, io, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blml_qa as q

ME = "qa_android"

def quiet(fn, *a):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fn(*a)
    return buf.getvalue().strip()

# 1. Clear the phone account's chat list and give it a presentable name.
s = q.session_for(ME)
s.call({"sub": {"topic": "me", "get": {"what": "sub"}}})
q.drain(s)
topics = [t["topic"] for f in s.backlog for t in (f.get("meta") or {}).get("sub", [])]
for t in topics:
    if t in ("me", "fnd", "sys", "slf"):
        continue
    c = s.call({"del": {"topic": t, "what": "topic", "hard": True}})
    if c["code"] >= 300:
        c = s.call({"leave": {"topic": t, "unsub": True}})
    print("cleared", t, c["code"])
print("rename", s.call({"set": {"topic": "me", "desc": {"public": {"fn": "Sam Tran"}}}})["code"])
s.ws.close()

# 2. The other people.
PEOPLE = [("shot_leo", "Leo Tran"), ("shot_mia", "Mia Pham"), ("shot_mom", "Mom"),
          ("shot_binh", "Uncle Binh"), ("shot_anna", "Anna Nguyen")]
for login, name in PEOPLE:
    print(quiet(q.cmd_newuser, login, name))

def befriend(peer):
    quiet(q.cmd_request, peer, ME)
    print("accept", peer, quiet(q.cmd_accept, ME, peer)[:40])

def say(who, to, text):
    out = quiet(q.cmd_send, who, to, text)
    if '"code": 2' not in out:
        print("SEND FAILED", who, to, out)
    time.sleep(0.4)

def group(owner, name, *members):
    gs = q.session_for(owner)
    topic = gs.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": name}}}}})["topic"]
    for m in members:
        uid = q.topic_for(m)
        print("invite", m, gs.call({"set": {"topic": topic, "sub": {"user": uid}}})["code"])
    gs.ws.close()
    return topic

# Oldest conversation first: the chat list sorts by latest activity.
befriend("shot_mia")
say("shot_mia", ME, "Did you see the photos from Sunday?")
say(ME, "shot_mia", "Yes! The one with grandpa is my favourite 😄")
say("shot_mia", ME, "Printing that one for sure")
quiet(q.cmd_note, ME, "shot_mia", "read")

# A stranger asking to chat: stays a pending request.
quiet(q.cmd_request, "shot_anna", ME)

family = group("shot_mom", "Family", ME, "shot_leo", "shot_mia", "shot_binh")
say("shot_mom", family, "Dinner on Sunday at ours 🍜")
say("shot_binh", family, "I'll bring dessert")
say(ME, family, "We'll be there by 6")
say("shot_mom", family, "Perfect ❤️")
quiet(q.cmd_note, ME, family, "read")

befriend("shot_leo")
say("shot_leo", ME, "Are we still on for badminton tomorrow?")
say(ME, "shot_leo", "Yes, court's booked for 7")
say("shot_leo", ME, "Great, I'll bring the shuttles 🏸")
say(ME, "shot_leo", "See you there 👍")
quiet(q.cmd_note, "shot_leo", ME, "read")
quiet(q.cmd_note, ME, "shot_leo", "read")

befriend("shot_mom")
say("shot_mom", ME, "Did you eat yet?")
say(ME, "shot_mom", "Just finished, don't worry 😊")
quiet(q.cmd_note, ME, "shot_mom", "read")
say("shot_mom", ME, "Call me when you land ❤️")

trip = group("shot_leo", "Weekend in Da Nang", ME, "shot_mia", "shot_binh")
say(ME, trip, "Booked the place by the beach 🏖️")
say("shot_leo", trip, "Nice! What time are we leaving Saturday?")
say(ME, trip, "Train at 7:40am, so let's meet at 7:00")
say("shot_mia", trip, "Works for me 👍")
say("shot_binh", trip, "I can drive if anyone needs a lift")
say("shot_mia", trip, "Yes please! I'll bring the snacks 🍜")
say(ME, trip, "Perfect. Weather looks good all weekend ☀️")
quiet(q.cmd_note, "shot_leo", trip, "read")
quiet(q.cmd_note, "shot_mia", trip, "read")
quiet(q.cmd_note, ME, trip, "read")
say("shot_leo", trip, "Can't wait 🎉")
say("shot_mia", trip, "Who's bringing the speaker?")
print(json.dumps({"family": family, "trip": trip}))
