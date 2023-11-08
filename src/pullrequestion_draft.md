I like spinners with my `ProgressUnknown()`, so here's collection of 110 of them. The first 89 are stolen (with credits) from https://github.com/briandowns/spinner, the rest (90-110) I had fun creating this evening.

Summary of the changes:
- Includes a `spinnercollection` of 110 spinners,
- Added the possibility of specifying spinners that are `AbstractVector{<:AbstractString}`. Were there any reason to restrict them to a single `Char`?
- `next!(prog, spinner=idx)` is equivalent to `next!(prog, spinner=spinnercollection[idx])`
- There a fun `demospinners()` function that shows them all in action, but also
  - `demospinners(idx)` to look at a specific spinner in the collection,
  - `demospinners(string)`, `demospinners(vector_of_chars)`, and `demospinners(vector_of_strings) to look at your own spinners, 
  - `demospinners(vector_of_vectors_of_strings)` will show all your spinners in a nicely aligned table. `demospinners()` is just `demospinners(spinnercollection)`.

Demo (the gif doesn't loop perfectly like the spinners for obvious reasons):
![spinners](https://github.com/timholy/ProgressMeter.jl/assets/7315599/64015cad-247c-45dd-9a0f-1ffbca1cbab8)

and so you can get things like this
![progressunknown](https://github.com/timholy/ProgressMeter.jl/assets/7315599/eddbe03f-0b48-4ed7-a2e7-8074ae37d33a)
