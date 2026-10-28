# Ubiquitous Language

This document describes the product language shared by streamers and developers.
It includes the intended multi-round workflow; the current implementation does
not yet support every behavior described here. It does not prescribe a database
model.

## Terms

- **Game library**: The collection of games available to a community. Removing a
  game from a wheel's pool does not delete it from the library.
- **Wheel format**: A reusable template of rules and starting configuration
  used to create a wheel. A format can create multiple independent wheels.
- **Wheel**: A particular instance created by a streamer for an activity, such
  as "Tonight's demos." It has a pool of eligible games and can be used for
  multiple voting rounds and spins. Changes to a wheel's pool do not change its
  format or other wheels.
- **Wheel UI** or **wheel visual**: The on-screen representation used to display
  and spin a wheel.
- **Pool**: The games currently eligible for voting and selection on a
  particular wheel. The pool can change over the wheel's lifetime; history
  records earlier results even after games leave it.
- **Voting round**: A period of collecting votes for the games eligible on a
  wheel. A new round starts with equal base chances and its own vote totals.
  Votes from previous rounds do not affect it.
- **Vote**: An expression of preference for an eligible game in a voting round,
  affecting that game's chance on the wheel.
- **Spin**: A selection from the wheel's current pool, using the applicable
  weights. A spin records a result; multiple spins may use the same round's
  vote weights.

## Example workflow

A streamer creates a demo wheel from a wheel format, with ten games in its pool.
They can spin with equal chances or open voting so votes affect the chances.

After a spin, the winner is removed from the pool by default. The streamer can
turn automatic removal off, in which case the winner remains eligible like any
other game. The spin result remains in history. The streamer can then:

- Spin again using the existing weights for games still in the pool; or
- Start a new vote when ready. Voting opens immediately for the remaining pool,
  with equal base chances and no votes carried over.

This can continue for as many spins or rounds as the streamer wants, including
until the pool is empty. Prior round and spin history remains available even
though its votes no longer affect a new round.

A future pool reset could repopulate a wheel according to rules. The reset
behavior and its rules are not defined here.
