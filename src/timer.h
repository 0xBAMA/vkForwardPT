#ifndef TIMER
#define TIMER

#include <chrono>
#include <sstream>
#include <iostream>
#include <algorithm>

#include <math.h>

using std::cout;
using std::endl;

#include <vk_types.h>
#include <vk_descriptors.h>
#include <vk_pipelines.h>
#include <vk_loader.h>

inline std::string timeDateString () {
	auto now = std::chrono::system_clock::now();
	auto inTime_t = std::chrono::system_clock::to_time_t( now );
	std::stringstream ssA;
	ssA << std::put_time( std::localtime( &inTime_t ), "%Y-%m-%d at %H-%M-%S" );
	return ssA.str();
}

inline std::string fixedWidthTimeString () {
	auto now = std::chrono::system_clock::now();
	auto inTime_t = std::chrono::system_clock::to_time_t( now );
	std::stringstream ssA;
	ssA << std::put_time( std::localtime( &inTime_t ), "[%H:%M:%S]" );
	return ssA.str();
}

//=============================================================================
//==== OpenGL Timer Query Wrapper =============================================
//=============================================================================
struct queryPair_GPU {
	queryPair_GPU ( string s ) : label( s ) {}
	string label;
	int tStampStart = -1;
	int tStampEnd = -1;
	float result = 0.0f;
};

struct queryPair_CPU {
	queryPair_CPU ( string s ) : label( s ) {}
	string label;
	std::chrono::time_point< std::chrono::system_clock > tStart;
	std::chrono::time_point< std::chrono::system_clock > tStop;
	float result;
};

class timerManager {
public:
	std::vector < queryPair_GPU > queries_GPU;
	std::vector < queryPair_CPU > queries_CPU;
	void gather () {
		for ( auto& q : queries_GPU ) {
			GLint timeAvailable = 0;
			while ( !timeAvailable ) { // wait on the most recent of the queries to become available
				glGetQueryObjectiv( q.queryID[ 1 ], GL_QUERY_RESULT_AVAILABLE, &timeAvailable );
			}

			GLuint64 startTime, stopTime; // get the query results, since they're both ready
			glGetQueryObjectui64v( q.queryID[ 0 ], GL_QUERY_RESULT, &startTime );
			glGetQueryObjectui64v( q.queryID[ 1 ], GL_QUERY_RESULT, &stopTime );
			glDeleteQueries( 2, &q.queryID[ 0 ] ); // and then delete them

			// get final operation time in ms, from difference of nanosecond timestamps
			q.result = ( stopTime - startTime ) / 1000000.0f;
		}
	}

	void clear () { // prepare for next frame
		queries_GPU.clear();
		queries_CPU.clear();
	}
};

class unscopedTimer {
public:
	queryPair_GPU q;

	std::chrono::time_point< std::chrono::steady_clock > tStart;
	std::chrono::time_point< std::chrono::steady_clock > tStop;

	unscopedTimer () : q( " " ) {}
	void tick () { // start the timers
		// GPU
		glGenQueries( 2, &q.queryID[ 0 ] );
		glQueryCounter( q.queryID[ 0 ], GL_TIMESTAMP );

		// CPU
		tStart = std::chrono::steady_clock::now();
	}

	void tock () { // end the timers
		// GPU
		glQueryCounter( q.queryID[ 1 ], GL_TIMESTAMP );
		GLint timeAvailable = 0;
		while ( !timeAvailable ) { // wait on the most recent of the queries to become available
			glGetQueryObjectiv( q.queryID[ 1 ], GL_QUERY_RESULT_AVAILABLE, &timeAvailable );
		}

		GLuint64 startTime, stopTime; // get the query results, since they're both ready
		glGetQueryObjectui64v( q.queryID[ 0 ], GL_QUERY_RESULT, &startTime );
		glGetQueryObjectui64v( q.queryID[ 1 ], GL_QUERY_RESULT, &stopTime );
		glDeleteQueries( 2, &q.queryID[ 0 ] ); // and then delete them

		// get final operation time in ms, from difference of nanosecond timestamps
		timeGPU = ( stopTime - startTime ) / 1000000.0f;

		// CPU
		tStop = std::chrono::steady_clock::now();
		timeCPU = std::chrono::duration_cast<std::chrono::microseconds>( tStop - tStart ).count() / 1000.0f;
	}

	// values in ms
	float timeGPU;
	float timeCPU;
};

inline timerManager* timerQueries;
inline vkQueryPool* queries;

class scopedTimer {
public:
	queryPair_CPU c;
	queryPair_GPU q;
	scopedTimer ( string label ) : c ( label ), q ( label ) {
		// GPU query prep
		glGenQueries( 2, &q.queryID[ 0 ] );
		glQueryCounter( q.queryID[ 0 ], GL_TIMESTAMP );

		// CPU query prep
		c.tStart = std::chrono::system_clock::now();
	}
	~scopedTimer () {
		// GPU query finish
		glQueryCounter( q.queryID[ 1 ], GL_TIMESTAMP );
		timerQueries->queries_GPU.push_back( q );

		// CPU query finish
		c.tStop = std::chrono::system_clock::now();
		c.result = std::chrono::duration_cast<std::chrono::microseconds>( c.tStop - c.tStart ).count() / 1000.0f;
		timerQueries->queries_CPU.push_back( c );
	}
};


// better design to just reuse the code
class scopedTimer {
public:
	unscopedTimer t;
	scopedTimer ( string label ) : t( label ) {
		t.tick();
	}
	~scopedTimer () {
		t.tock();

		// GPU query finish
		timerManager->queries_GPU.emplace_back( t.q );
		timerManager->queries_CPU.emplace_back( t.c );
	}
};

#endif
