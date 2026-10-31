# Ubiquitous Language

This document defines shared domain language for discussing and developing
Backlog Wheel. UI labels may differ where another phrase is clearer in context.
The definitions describe the intended domain; not all relationships are
implemented yet, and they do not prescribe a database model.

- **User**: A person who interacts with the application directly or through an
  integration. A user may have an application account, but one is not required.
- **Community**: A group and the context for its activity in the application,
  including its game library, voting sessions, and settings.
- **Participant**: A user who takes part in a community's activities, such as
  voting. A participant may interact through an integration or directly with
  the application.
- **Community administrator**: A user authorized to manage a particular
  community. A community administrator can also perform participant actions
  in that community, without requiring a separate participant role.
- **Site administrator**: A user authorized to administer the application as
  a whole. Site administration is independent of involvement in any
  particular community.

A user can administer one community, participate in another, and be a site
administrator. Site administration does not require involvement in a
community.

- **Game library**: The collection of games available to a community. A game
  can have attributes, including its wheel-inclusion setting, used to select
  candidates for a voting session.
- **Wheel inclusion**: A library-level setting that can be used when selecting
  games for a session's pool. It is distinct from membership in any particular
  pool.
- **Wheel format**: A reusable template of rules and starting configuration
  used to create a voting session. A format can be used to create multiple
  sessions.
- **Voting session**: A streamer's game-selection activity, with a pool of
  eligible games, zero or more voting rounds, and zero or more spins. Voting is
  optional. A session's pool can change independently of its format and other
  sessions.
- **Pool**: The games currently eligible for voting and selection in a
  particular voting session. Removing a game from a pool does not delete it
  from the library, change its library-level wheel-inclusion setting, or
  remove it from another session's pool.
- **Voting round**: One period of collecting votes within a voting session,
  with its own votes. A new round starts with equal base chances for the current
  pool and no votes carried over from previous rounds.
- **Vote**: An expression of preference for an eligible game in a voting round.
  Votes influence the game's chance of selection.
- **Spin**: A selection from a voting session's current pool using the
  applicable weights. A spin can use a voting round's votes or happen without
  voting. A round's votes are not reused for another spin. A session spin's
  result and the weights used are recorded.
- **Wheel UI** or **wheel visual**: The on-screen representation used to display
  options and animate a spin.
- **Quick Wheel**: A separate experience for spinning a free-form list of
  entries. Its entries need not be games in a library, and its spins are not
  recorded in the game-selection session's spin history.
