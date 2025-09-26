//  Boost next_prior.hpp header file  ---------------------------------------//

//  (C) Copyright Dave Abrahams and Daniel Walker 1999-2003.
//  Copyright (c) Andrey Semashev 2017
//
//  Distributed under the Boost Software License, Version 1.0.
//  (See accompanying file LICENSE_1_0.txt or copy at
//  http://www.boost.org/LICENSE_1_0.txt)

//  See http://www.boost.org/libs/utility for documentation.

//  Revision History
//  13 Dec 2003  Added next(x, n) and prior(x, n) (Daniel Walker)

#ifndef BOOST_NEXT_PRIOR_HPP
#define BOOST_NEXT_PRIOR_HPP

#include <iterator>

namespace boost {

template <class T>
T next(T x) { return ++x; }

template <class T, class Distance>
T next(T x, Distance n) {
    std::advance(x, n);
    return x;
}

template <class T>
T prior(T x) { return --x; }

template <class T, class Distance>
T prior(T x, Distance n) {
    std::advance(x, -n);
    return x;
}

} // namespace boost

#endif // BOOST_NEXT_PRIOR_HPP
