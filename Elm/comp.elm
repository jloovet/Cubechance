port module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Date
import Dict
import Time
import Task

import Http

import Base

main =
    programWithFlags
        { init = init
        , update = update
        , view = view
        , subscriptions = subs
        }

port title : String -> Cmd a

type alias Flags =
    { compId : String }

type alias Model =
    { compId : String
    , comp : Maybe Base.Competition
    , people : List Base.Person
    , selected : Maybe Selected
    , error : Maybe String
    , sortBy : Maybe String
    , matching : List Base.Person
    , search : String
    }

type Selected
    = SelectEvent Base.Person
    | Waiting Base.Person String
    | Loaded Base.Person String (List Float)

type Msg
    = LoadComp
    | ParseComp (Result Http.Error String)
    | SelectedPerson Base.Person
    | SelectedOther String
    | ParseOther (Result Http.Error String)
    | SelectedEvent String
    | ParseChances (Result Http.Error String)
    | SortBy (Maybe String)

init : Flags -> (Model, Cmd Msg)
init flags =
    let (model, cmd) = 
            update LoadComp <|
                { compId = flags.compId
                , comp = Nothing
                , people = []
                , selected = Nothing
                , error = Nothing
                , sortBy = Nothing
                , matching = []
                , search = ""
                }
    in (model, Cmd.batch <| [Task.perform SelectedEvent <| Task.succeed "333", cmd])

decodeCompAndPeople =
    D.map2
        (\comp people -> (comp, people))
        (D.field "comp" Base.decodeComp)
        (D.field "people" <| D.list Base.decodePerson)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        LoadComp ->
            model !
            [ Http.send ParseComp
                <| Http.getString
                    <| "api/comp/" ++ model.compId
            ]

        ParseComp (Ok text) ->
            case D.decodeString decodeCompAndPeople text of
                Ok (comp, people) ->
                    { model
                        | comp = Just comp
                        , people = people
                    } ! 
                    [ title <| comp.name
                    ]
                Err err ->
                    { model | error = Just <| Debug.log "Error" <| toString err } ! []

        SelectedPerson p ->
            case model.selected of
                Just (SelectEvent e) -> { model | selected = Nothing } ! []
                _                    -> { model | selected = Just <| SelectEvent p } ! []

        SelectedOther name ->
            { model
            | search = name
            } !
            [ Http.send ParseOther
                <| Http.getString
                    <| "api/people/" ++ name
            ]
        
        ParseOther r ->
            case r of
                Ok res ->
                    case D.decodeString (D.list Base.decodePerson) res of
                        Ok matching ->
                            { model
                            | matching = matching
                            } ! []
                        Err e -> { model | error = Just <| toString e } ! []
                Err e -> { model | error = Just <| toString e } ! []

        SelectedEvent e -> 
            case model.selected of
                Just (SelectEvent p) ->
                    { model
                    | selected = Just <| Waiting p e
                    , matching = []
                    , search = ""
                    } !
                    [ Http.send ParseChances
                        <| Http.getString
                            <| "api/place/" ++ model.compId ++ "/" ++ p.id ++ "/" ++ e
                    ]
                _ -> model ! []

        ParseChances res ->
            case (res, model.selected) of
                (Ok json, Just (Waiting p e)) ->
                    case D.decodeString decodePlaces json of
                        Ok places ->
                            { model | selected = Just <| Loaded p e places} ! []
                        Err e -> { model | error = Just <| toString e } ! []
                (Err e, _) -> { model | error = Just <| toString e } ! []
                _ -> model ! []

        ParseComp (Err err) ->
            { model | error = Just <| toString err } ! []

        SortBy x ->
            { model | sortBy = x } ! []

decodePlaces = D.list D.float

view model =
    let compLink = "https://www.worldcubeassociation.org/competitions/" ++ model.compId
    in div [] 
        [ a [ href "/index.html" ] [ text "←" ]
        , br [] []
        , text "Add person: "
        , input [ placeholder "Name", value model.search, onInput SelectedOther ] []
        , case model.matching of
            [] -> text ""
            _ ->
                table []
                <| tr [] [th [] [text "Name"], th [] [text "Wca ID"]]
                :: List.map (\p ->
                    tr [] 
                        [ td [ onClick <| SelectedPerson p ] [text p.name]
                        , td [] [text p.id]]
                    ) model.matching
        , case model.selected of
            Just (Loaded person event places) ->
                let placesWithIndexed =
                        List.indexedMap (\i place -> (i, place)) places
                in div [] <|
                    p [] [ text <| person.name ++ " has the following chances in "
                         , genIcon event
                         , text ":"]
                    :: List.filterMap (\ (i, chance) ->
                        if chance > 0.01
                           then Just <| p [] [ text <| toString (i + 1) ++ ": " ++ Base.stf2 (chance * 100) ++ "%" ]
                           else Nothing
                    ) placesWithIndexed
            _ -> text ""
        , case model.comp of
            Just comp ->
                div []
                    [ div [id "center"] [
                        h1 [id "title"] [text comp.name]
                        , a [ id "compLink", href compLink ] [ text "(On WCA)" ]
                    ]
                    , case model.selected of
                        Just (SelectEvent per) ->
                            viewCompetitors model.sortBy comp model.people <| Just per
                        _ -> viewCompetitors model.sortBy comp model.people Nothing
                    ]
            _ ->
                p [id "loading"] [text "Loading..."]
        ]

compareP people method c1 c2 =
    case ( findPerson c1.id people
         , findPerson c2.id people) of
        (Just p1, Just p2) ->
            case method of
                Just event ->
                    case ( List.any (\a -> a == event) c1.events
                         , List.any (\a -> a == event) c2.events ) of
                        (False, _) -> GT
                        (_, False) -> LT
                        _ -> case ( Dict.get event p1.avgs
                                  , Dict.get event p2.avgs) of
                            ( Just (Base.Time t1)
                            , Just (Base.Time t2))  -> compare t1 t2
                            (Just Base.DNF, Just _) -> GT
                            (Just _, Just Base.DNF) -> LT
                            (Nothing, Just _)       -> GT
                            (Just _, Nothing)       -> LT
                            _                       -> EQ
                Nothing -> compare p1.name p2.name
        _ -> EQ

viewCompetitors sort competition people selected =
    let competitors = 
            List.filterMap
            (\competitor ->
                case findPerson competitor.id people of
                    Nothing -> Nothing
                    Just person -> Just <| viewCompetitor selected competition competitor person
            )
            (List.sortWith (compareP people sort) competition.competitors)
        person =
            case selected of
                Just x ->
                    if not <| List.any (\p -> x.id == p.id) competition.competitors
                        then [ viewCompetitor selected competition (Base.Competitor x.id x.name <| Dict.keys x.times) x ]
                        else [  ]
                _ -> []
    in table [id "list"]
        <| genHeader competition
        :: person
        ++ competitors

viewCompetitor select competition competitor person =
    let personLink = "https://www.worldcubeassociation.org/persons/" ++ person.id
        tClass =
            case select of
                Just x -> 
                    if x.id == person.id
                       then "competitor selected"
                       else "competitor deselected"
                _ -> "competitor"
    in tr [class tClass]
        <|
        [ td [class "comp_name"] [
            a [ onClick <| SelectedPerson person ] [ text person.name]
        ]
        ] ++ List.map (\event -> displayEvent select event competitor person) competition.events

genHeader competition =
    tr [class "comp-events" ] <|
        th [ class "name", onClick <| SortBy Nothing ] [ text "Name" ]
     --:: th [ class "comp-id"] [ text competition.id ]
     :: List.map
            (\event ->
                th [ class "event", onClick <| SortBy (Just event) ]
                [ span [class <| "cubing-icon event-" ++ event ] []
                ]
            )
            competition.events

displayEvent select event competitor person =
    let isSelected = 
            case select of
                Just x -> x.id == person.id
                _ -> False
    in case Dict.get event person.avgs of
        Nothing -> td [class "event"] []
        Just avg ->
            if List.any (\a -> a == event) competitor.events then
                let click = 
                        case select of
                            Just _ -> [ onClick <| SelectedEvent event ]
                            _ -> []
                in td ([class "event"] ++ click)
                    [ text <| Base.viewTime avg ]
            else td [class "event"] []

genIcon event =
    span [ class <| "cubing-icon event-" ++ event ] []



findPerson : String -> List Base.Person -> Maybe Base.Person
findPerson id people =
    List.head
        <| List.filter (\person -> person.id == id) people

subs model = Time.every (Time.second * 10) <| always LoadComp
