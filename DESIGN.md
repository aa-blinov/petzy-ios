---
name: petzy-ios
description: The Petzy app for iOS. One warm accent on the system palette, the system type scale, and the system controls, in Russian.
colors:
  primary: "#C46B40"
  accent-dark: "#E8946B"
  neutral-bg: "#FAF6EF"
  danger: "the system red"
typography:
  body:
    fontFamily: "SF Pro Text, system-ui"
    fontSize: "17pt"
    fontWeight: 400
    lineHeight: "system"
  title:
    fontFamily: "SF Pro Display, system-ui"
    fontSize: "34pt"
    fontWeight: 600
    lineHeight: "system"
    letterSpacing: "system"
  headline:
    fontFamily: "SF Pro Text, system-ui"
    fontSize: "17pt"
    fontWeight: 600
  subheadline:
    fontFamily: "SF Pro Text, system-ui"
    fontSize: "15pt"
    fontWeight: 400
  footnote:
    fontFamily: "SF Pro Text, system-ui"
    fontSize: "13pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro Text, system-ui"
    fontSize: "12pt"
    fontWeight: 400
rounded:
  md: "12px"
  lg: "16px"
  capsule: "100%"
spacing:
  xs: "2px"
  sm: "4px"
  md: "8px"
  lg: "12px"
  xl: "16px"
---

# Design system: petzy-ios

## Overview

**Creative North Star: "the native surface"**

The app is a SwiftUI client for a pet health diary, and it looks like one:
the system controls, the system type scale, the system signs, and one warm
accent from the brand. Almost every colour, every size and every corner in
the interface is something iOS already decided. What the project adds is the
accent, the wording and the arrangement.

The interface is Russian. The dates, the numbers and the plural forms follow
the `ru_RU` locale, and the app pins it, so an English device shows Russian
dates and Russian money formatting rather than something half translated.

What the project rejects: drawn controls, a palette of its own beyond the
accent, and a copy of the web app's gestures. The web app decides the
behaviour and the Russian wording; the port took the screens across and
left the gestures behind.

Key characteristics:

- One accent, two values, one for the light scheme and one for the dark.
- The system sign for every action, and one meaning per sign.
- The failure is a sentence on the screen, not only a colour.
- The layout holds at the accessibility text sizes.

## Colors

The palette is the system's, with one exception. There is no stylesheet and
no colour constant beyond `Accent` in `Petzy/App/Accent.swift`.

### Primary

- **Warm brown-orange** (`#C46B40`): the accent in the light scheme. It is
  the tint of the app, and it paints the buttons, the selected state and the
  chart.
- **Warm brown-orange, light** (`#E8946B`): the accent in the dark scheme.
  A dark accent on a dark background is unreadable, so the value is lighter
  there rather than the same one in both.

The two values live in one place, as a `UIColor` that reads the trait
collection, so a screen never has to ask which scheme is in force.

### Neutral

- **The system background and the system label colours.** A row is a list
  row, the secondary text is the system's secondary colour, and the tertiary
  text is the system's tertiary colour.
- **Cream** (`#FAF6EF`): the square of the app icon. It is the brand
  background of the icon and of nothing else in the app.

### Status

- **Red** (`#red`): an overdue dose, an expired document, a record with
  nothing left in it, and the delete action in a swipe.
- **The system orange** (`#orange`): used once, in the medical card's block
  for the visit, on the line that says what changed since the last visit.

### The colour of a custom type

A record type of the person's own carries a colour they pick. The palette
is fixed at eleven names, because the server accepts eleven names and not
any hue: brown, orange, red, green, purple, teal, cyan, yellow, blue, pink
and gray. The picker shows the Russian name of the colour, the app sends the
name, and the colour itself is not drawn anywhere in the app. Only a custom
type has one; the built-in types do not.

### Named rules

**The accent means the app.** The warm colour marks the app's own controls
and the data it owns. It is not a decoration and it is not a category.

**Colour never carries the message alone.** An overdue dose is red and says
in words what is wrong. A record with no medication left is red and says
how much is left. A person who cannot see the colour still gets the fact.

**One accent, two values.** The light and the dark value of the accent are
the only two colours the project defines, and they are defined together.

## Typography

**Display Font:** SF Pro Display. **Body Font:** SF Pro Text.

Every size is a system text style, so the whole interface grows with the
accessibility setting and nothing has to be scaled by hand.

| Role | Style | Where it is used |
| --- | --- | --- |
| Display | `.largeTitle.weight(.semibold)` | The heading of the first-run screen. |
| Title | `.title2.weight(.semibold)` | The name of the pet on the medical card. |
| Section title | `.title3.weight(.semibold)` | The number of records on a medical card tile. |
| Headline | `.headline` | The name of a medication course, the title of a row. |
| Body | `.body` | One paragraph of prose, once. |
| Secondary | `.subheadline` | The workhorse: schedules, doses, stock, comments, the day headers. |
| Caption | `.caption` | The status under a tile, the subtext under a stock amount. |
| Footnote | `.footnote` | The least important line on a screen. |

Weights are added where a line has to win: `.semibold` on a title, on the
count of a tile, on the chevron that says a tile opens, and on the name of a
medication. `.medium` marks the amount of medication left and the tag next
to a course name.

Two sizes are fixed rather than styled: the illustration on the first-run
screen at 72 points, and the name of a pet on the summary card at 28 points.
They are the only two places where the type does not scale.

The plural is part of the typography. Counts are written out, in the right
form for the number: "запись", "записи", "записей", and the same for the
waiting records in the offline queue.

## Layout

One column, one list at a time, and the record in the middle of the screen.

The feed is a `List` with the pet's card at the top, then a section per
day, and a row per record. The day header is a word: "Сегодня", "Вчера", or
a date in the usual Russian form. The next page is asked for when the
person reaches the end.

The medical card is a grid of tiles, two across, and a tile is a rounded
rectangle with a count and a status. The feed, the medication list and the
documents are lists with plain separators.

The spacing scale is loose rather than strict: 2, 4, 6, 8, 10, 12, 16, 20
and 32 points are all in use, and the gap inside a stack is usually 6 or 10
points. The scale follows what the screen needs rather than a grid.

### The layout moves with the text size

Two places change shape at the accessibility sizes, and they change for the
same reason: a label that loses its width breaks by letters.

- **A medical card tile.** At the large sizes the sign moves above the
  title instead of beside it, so the title keeps the full width.
- **The weekdays of a medication course.** Seven chips in a row leave about
  40 points each and "Пн" breaks. At the large sizes they go into a grid of
  four.

## Elevation & depth

The depth is the system's. There is no shadow, no gradient and no custom
elevation anywhere in the project.

What stands out from the ground is the system list row and the system card
material. The one shape the project draws itself is the medical card tile,
and it is flat: a `quaternary` fill at 40 percent opacity inside a rounded
rectangle of 12 points, with no shadow at all.

## Shapes

- **The tile.** A rounded rectangle of 12 points, with a `quaternary` fill
  at 40 percent opacity.
- **The pet photo.** Clipped to a rounded rectangle of 12 points.
- **The pet photo on the profile.** Clipped to a rounded rectangle of 16
  points.
- **The chip.** A capsule: the tag next to a medication name, and the
  selected weekday. A selected weekday is a capsule filled with the accent
  at 18 percent opacity.

There is no shadow and no border drawn by hand. The borders in the app are
the system's separators.

## Components

### The button

The system button, in four styles, and no others: plain, borderless, bordered
and prominent, once each.

- **Plain** is the default in this app. It removes the chrome so a row can
  hold a card or a weekday without looking like a button.
- **Borderless** is for a row that is itself the action.
- **Bordered** is for a small secondary action inside a row, such as
  "Пополнить" next to the remaining amount.
- **Bordered prominent** is used once, for the button on the first-run
  screen.

The accent colour is kept. The background and the shadow of the system
control are stripped, and nothing else is drawn.

### The tile

A medical card tile: the sign and the title, the number of records in a
title-3 semibold, and the status in a caption in red when something is
overdue. A chevron in the trailing corner says the tile opens, and it is
drawn by the app rather than by the system, because a link inside a list
row breaks the navigation.

### The row

A list row with the title in a headline, the detail in a subheadline, and a
sign on the leading edge. The sign comes from the server's type catalogue
and is translated to a system sign by `EventIcon`, because the server sends
Lucide names and `Image(systemName:)` draws nothing for a name it does not
know.

### The chip

A capsule with a caption-weight-medium label. It carries the state of a
course, and the days of a schedule.

### The banner

A section at the top of a list, not a floating toast. The offline banner
carries the `wifi.slash` sign and says in words that there is no connection
and that what is on screen is the saved copy. The queue banner counts the
records that are waiting and a button to send them now.

### The chart

One frame of 210 points. A type with a value is drawn as a line over an
area filled with the accent at 18 percent opacity, with a point marked when
there is only one bucket. A counted type is drawn as bars, because an
average of a count is not a number. The axis of a value chart is scaled to
the values, and the axis of a counted chart starts at zero.

### The empty state

`ContentUnavailableView` from the system, with the system's signs. A section
that failed to load says so and carries a "Повторить" button.

### The sign

One meaning, one sign: `plus` for creating, `square.and.arrow.up` for
sharing, `arrow.down.doc` for the export, `clock` for a record that is
waiting to be sent, `wifi.slash` for the offline banner, and `chevron.right`
for a tile that opens.

## Do's and Don'ts

### Do:

- **Do** use the system control and keep the accent. Strip the background
  and the shadow, and leave the rest alone.
- **Do** say what happened in words next to the colour.
- **Do** keep the touch target at 44 points or more, and make a tappable
  row a `Button` rather than a gesture.
- **Do** move a label above its neighbour when the accessibility size leaves
  it too little room.
- **Do** write the count in the right plural form.
- **Do** use one sign for one meaning, and take it from the system.

### Don't:

- **Don't** draw a control that the system already has.
- **Don't** use a colour outside the system palette and the accent.
- **Don't** put a second `NavigationLink` in a row. The row becomes the
  link and the navigation goes to the wrong place.
- **Don't** leave a `role: .cancel` button in a confirmation dialog. It is
  hoisted out of the popover and never drawn.
- **Don't** rely on a swipe as the only way to delete. The row carries a
  red button as well, and the full swipe is off.
- **Don't** add a colour of your own to a state. The system's red and the
  system's orange are the two that exist, and a custom type carries the
  name of the colour the person chose.
