module postrock;

import beard.io;
import beard.vector : pushBack, pushFront;

import std.array : split, join;
import std.bigint : BigInt;
import std.process : getenv;

/// Generic command line error.
class CmdLineError : Throwable {
    this(string error) { super(error); }
}

/// Thrown when a user supplies a malformed command-line argument such as ---arg
class BadCommandLineArgument : CmdLineError {
    this(string error) { super(error); }
}

/// When a user supplies a flag that is not known.
class UnknownCommandLineArgument : CmdLineError {
    this(string error) { super(error); }
}

/// This is thrown when an argument requires a value but the user supplied none.
class BadCommandLineArgumentValue : CmdLineError {
    this(string error) { super(error); }
}

int maxLeftColumnWidth = 40;

/// Command-line argument parser object.
class Parser {
    struct State {
        this(string[] *_args) { args = _args; }

        bool empty() { return argIdx >= args.length; }
        ref string front() { return (*args)[argIdx]; }

        char firstChar() { return front()[argOffset]; }
        char charAt(int idx) { return front()[argOffset + idx]; }

        string substring() { return front()[argOffset..$]; }

        void advanceOffset(int incr) {
            argOffset += incr;
            if (argOffset >= front().length)
                popArgument();
        }

        // advance pointer, keeping argument in args
        void saveArgument() {
            if (nextSaveIdx < argIdx)
                (*args)[nextSaveIdx] = (*args)[argIdx];
            nextSaveIdx += 1;

            popArgument();
        }

        void popArgument() {
            argIdx += 1;
            argOffset = 0;
        }

        string[] *args;
        // which argument currently looking at
        int       argIdx = 1;
        // offset used to keep track of where parser is within current option
        int       argOffset = 0;
        // idx where last saved argument was
        int       nextSaveIdx = 1;
    }

    interface AbstractValue {
        void parse(ref State state);
    }

    class Value(T) : AbstractValue {
        this(T *ptr) { valPtr_ = ptr; }

        private static void parseHelper(U)(ref U val, ref State state) {
            static if (is(U : bool)) {
                val = true;
            }
            else static if (is(U : string)) {
                if (state.empty)
                    throw new BadCommandLineArgumentValue(state.front);
                val = state.substring;
                state.popArgument;
            }
            else static if (is(U V : V[])) {
                val.length += 1;
                parseHelper(val[val.length - 1], state);
            }
            else {
            }
        }

        void parse(ref State state) {
            parseHelper(*valPtr_, state);
        }

        T* valPtr_;
    }

    class ShowHelp : AbstractValue {
        this(Parser parser) { parser_ = parser; }
        private Parser parser_;

        void parse(ref State state) { parser_.showHelp; }
    }

  private:
    struct Help {
        this(string _help) { help = _help; }

        ulong leftColWidth() {
            auto ret = (args.length - 1) * 2;
            foreach (arg ; args) {
                ret += 2;
                if (arg.length > 1)
                    ret += arg.length;
            }
            return ret;
        }

        string help;
        string[] args;
    }

    void addDefaultHelpOption() {
        if ("h" in optionMap_ && "help" in optionMap_)
            return;

        auto helpShower = new ShowHelp(this);

        auto help = Help("show help");
        if (! ("h" in optionMap_)) {
            pushBack(help.args, "h");
            optionMap_["h"] = helpShower;
        }

        if (! ("help" in optionMap_)) {
            pushBack(help.args, "help");
            optionMap_["help"] = helpShower;
        }

        pushFront(helps_, help);
    }

  public:
    ref Parser opCall(T)(string args, T *storage, string helpString) {
        auto vals = split(args, ",");
        auto optValue = new Value!T(storage);
        auto help = Help(helpString);

        foreach (val ; vals) {
            pushBack(help.args, val);
            optionMap_[val] = optValue;
        }

        pushBack(helps_, help);

        return this;
    }

    ref Parser banner(string banner) {
        banner_ = banner;
        return this;
    }

    /// @brief Parse the command line.
    /// @detailed This will also add -h/--help options to show the help if
    ///           such options have not already been added.
    void parse(string[] *args) {
        auto state = State(args);

        addDefaultHelpOption;

        while (! state.empty) {
            if ('-' != state.firstChar) {
                state.saveArgument;
                continue;
            }

            auto front = state.front;
            if (1 == front.length)
                throw new BadCommandLineArgument(front);

            if ('-' == state.charAt(1)) {
                if (2 == front.length) {
                    state.popArgument;
                    while (! state.empty)
                        state.saveArgument;
                    break;
                }

                string search = front[2..$];
                state.popArgument; // advance past long option
                auto value = optionMap_.get(search, null);
                if (! value)
                    throw new UnknownCommandLineArgument(front);

                value.parse(state);
            }
            else {
                // parse short option.. maybe more than one
                state.advanceOffset(1);
                do {
                    string search = "" ~ state.firstChar;

                    auto value = optionMap_.get(search, null);
                    if (! value)
                        throw new UnknownCommandLineArgument(front);

                    state.advanceOffset(1); // advance past option
                    value.parse(state);
                } while (state.argOffset);
            }
        }

        args.length = state.nextSaveIdx;
    }

    // show help (-h/--help)
    void showHelp() {
        shownHelp_ = true;
        if (banner_.length)
            println(banner_);

        // get maximum column width
        ulong leftColWidth = 0;
        foreach (help ; helps_) {
            auto width = help.leftColWidth;
            if (width > leftColWidth)
                leftColWidth = width;
        }

        leftColWidth += 4; // 2 spaces either side
        if (leftColWidth > maxLeftColumnWidth)
            leftColWidth = maxLeftColumnWidth;

        foreach (help ; helps_) {
            string leftCol = "";
            foreach (arg ; help.args) {
                if (leftCol.length) leftCol ~= ", ";
                if (arg.length > 1)
                    leftCol ~= "--" ~ arg;
                else
                    leftCol ~= "-" ~ arg;
            }

            print("  " ~ leftCol);
            auto nSpaces = leftColWidth - leftCol.length - 4;
            while (nSpaces) {
                print(' ');
                nSpaces -= 1;
            }
            print("  ");
            println(help.help);
        }
    }

    /// Has the help been displayed yet?
    bool shownHelp() { return shownHelp_; }

  private:
    bool                  shownHelp_ = false;
    AbstractValue[string] optionMap_;
    Help[]                helps_;
    string                banner_;
}
// vim:ts=4 sw=4
