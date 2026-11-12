-- Templates for new diagrams: one example per diagram type that uses every element
-- of the catalog, in a working order with section comments, so you start from a
-- diagram that renders and delete what you don't need.
-- Settings that exclude each other or restyle everything are commented out.
return {
  sequence = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Checkout
header draft
footer page %page% of %lastpage%
caption Figure 1: checkout flow
skinparam shadowing false
' !theme plain
autonumber
hide footbox

' ==== participants ====
actor Customer
boundary "Web UI" as UI
control Checkout
entity Cart
database DB
collections Items
queue Events
box "Payments" #LightBlue
  participant "Payment Gateway" as PG
end box

' ==== messages ====
Customer -> UI: open cart
activate UI
UI -> Checkout: checkout(cart)
activate Checkout
Checkout -> Checkout: validate
note left: a self call
Checkout ->> Events: cart.checked_out
note right: async, no reply
...a few seconds later...

== Payment ==
alt card accepted
  Checkout -> PG: charge(amount)
  PG --> Checkout: ok
else declined
  PG --> Checkout: declined
  Checkout --> UI: error
end
opt has coupon
  Checkout -> DB: apply coupon
end
loop each item
  Checkout -> Items: reserve(item)
end
par
  Checkout -> Events: notify warehouse
else
  Checkout -> Events: notify customer
end
break out of stock
  Checkout --> UI: sorry
end
critical save the order
  create Order
  Checkout -> Order: new
  Order -> DB: insert
end
group audit
  Checkout -> DB: log
end
|||

' ==== notes ====
note left of Customer: note left
note over UI, Checkout: note over two participants
note over DB
  a multi-line
  note
end note
ref over Checkout, DB: see "Persistence"

Checkout --> UI: done
deactivate Checkout
return receipt
destroy Order

legend right
  ->  sync   -->  reply   ->>  async
endlegend
@enduml]],

  class = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Shop model
header draft
footer generated with puml.nvim
caption Figure 1: domain model
skinparam shadowing false
' !theme plain
hide empty members
left to right direction
' top to bottom direction

' ==== classes ====
package shop {
  abstract class Product {
    -name: String
    +price(): Money
  }
  class Book
  interface Shippable
  enum Status {
    NEW
    PAID
    SHIPPED
  }
  annotation Audited
}
namespace billing {
  class Invoice
}
class Order {
  -status: Status
  +total(): Money
}
class Line
class Customer

' ==== relations ====
Product <|-- Book
Shippable <|.. Book
Order *-- Line
Customer o-- Order
Line --> Product
Order ..> Status
Order "1" --> "*" billing.Invoice : bills

' ==== notes ====
note right of Order: aggregate root
note "a floating note" as N1
N1 .. Book

legend right
  <|~-~- extension   *~-~- composition   o~-~- aggregation
endlegend
@enduml]],

  activity = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Order handling
header draft
footer generated with puml.nvim
caption Figure 1: order flow
skinparam shadowing false
' !theme plain

|Customer|
start
:place order;
note right: a note
|Shop|
:check order;
if (in stock?) then (yes)
  :reserve items;
else (no)
  :back-order;
endif
if (payment?) then (card)
  :charge card;
elseif (invoice?) then (yes)
  :send invoice;
else (none)
  :cancel;
  stop
endif
switch (shipping?)
case (express)
  :ship today;
case (standard)
  :ship this week;
endswitch
while (more items?) is (yes)
  :pack item;
endwhile (no)
repeat
  :print label;
repeat while (label ok?) is (no)
fork
  :email customer;
fork again
  :update stock;
end fork
split
  :archive order;
  kill
split again
  :notify courier;
end split
partition Delivery {
  -> handed over;
  :deliver;
}
group Feedback
  :ask for a review;
end group
if (returned?) then (yes)
  :refund;
  (A)
  detach
endif
(A)
:close order;
end

legend right
  stop = end of flow, end = end of all flows
endlegend
@enduml]],

  usecase = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Online shop
header draft
footer generated with puml.nvim
caption Figure 1: use cases
skinparam shadowing false
' !theme plain
hide empty members
left to right direction
' top to bottom direction

' ==== actors ====
actor Customer
actor "Shop Admin" as Admin
actor User

' ==== use cases ====
rectangle Shop {
  (Browse)
  usecase "Place order" as UC1
  (Pay)
  (Apply coupon)
}
package Backoffice {
  (Manage stock)
}

' ==== relations ====
User <|-- Customer
Customer --> (Browse)
Customer --> UC1
Admin --> (Manage stock)
UC1 .> (Pay) : include
(Apply coupon) .> UC1 : extends

' ==== notes ====
note right of Admin: internal staff
note "a floating note" as N1
N1 .. (Browse)

legend right
  include = always, extends = optional
endlegend
@enduml]],

  component = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Shop deployment
header draft
footer generated with puml.nvim
caption Figure 1: components
skinparam shadowing false
' !theme plain
hide empty members
left to right direction
' top to bottom direction

' ==== elements ====
actor User
[Web UI]
component "Order Service" as OS
() "REST API" as API
node Server {
  [Worker]
}
cloud CDN {
  [Assets]
}
database DB
queue Events
artifact "orders.jar" as Jar
storage Files
package Libraries {
  [Common]
}
folder Config {
  [settings]
}
frame Monitoring {
  [Metrics]
}
rectangle Payments {
  component Gateway {
    port p1
  }
}

' ==== links ====
User --> [Web UI]
[Web UI] --> API
API --> OS
OS --> DB
OS --> Events
Events --> [Worker]
OS ..> [Common] : use
Jar ..> OS
[Assets] --> [Web UI]
[Worker] --> Files
OS --> p1

' ==== notes ====
note right of OS: the core service
note "a floating note" as N1
N1 .. DB

legend right
  --> link   ..> dependency
endlegend
@enduml]],

  state = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Order lifecycle
header draft
footer generated with puml.nvim
caption Figure 1: states
skinparam shadowing false
' !theme plain

' ==== states ====
state New
Paid : payment received
state check <<choice>>
state split <<fork>>
state merge <<join>>
state Shipping {
  [*] --> Packing
  Packing --> InTransit : packed
  --
  [*] --> Invoicing
  Invoicing --> Invoiced
}

' ==== transitions ====
[*] --> New
New --> check : submit
check --> Paid : [paid]
check --> New : [unpaid]
Paid --> split
split --> Shipping
split --> Archive
Shipping --> merge
Archive --> merge
merge --> Done
Done --> Shipping[H] : reopen
Done --> [*]

' ==== notes ====
note right of Paid: money is in
note "a floating note" as N1

legend right
  [*] = start / end, [H] = back to the last sub-state
endlegend
@enduml]],

  object = [[
@startuml
' ==== diagram-wide settings (delete what you don't need) ====
title Order example
header draft
footer generated with puml.nvim
caption Figure 1: objects
skinparam shadowing false
' !theme plain
hide empty members
left to right direction
' top to bottom direction

' ==== objects ====
object alice {
  name = "Alice"
  email = "alice@example.com"
}
object order42
map prices {
  book => 12.90
  pen => 1.50
}

' ==== links ====
alice --> order42
order42 --> prices

' ==== notes ====
note "a floating note" as N1
N1 .. alice

legend right
  objects at one moment in time
endlegend
@enduml]],

  mindmap = [[
@startmindmap
* Project
** Goals
*** Faster checkout
*** Fewer returns
**_ a boxless node
** Risks
*** Budget
left side
** Team
*** Design
*** Backend
right side
** Timeline
@endmindmap]],

  wbs = [[
@startwbs
* Shop relaunch
** Design
*** Wireframes
*** Visual design
**< Research
*** Interviews
**> Build
*** Frontend
*** Backend
@endwbs]],

  gantt = [[
@startgantt
Project starts 2025-01-01
saturday are closed
sunday are closed
[Design] requires 10 days
[Build] requires 20 days
[Build] starts at [Design]'s end
[Test] requires 5 days
[Test] starts at [Build]'s end
[Release] happens at [Test]'s end
[Design] is 100% completed
[Build] is 40% completed
@endgantt]],

  empty = [[
@startuml
${0}
@enduml]],
}
