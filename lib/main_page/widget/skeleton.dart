import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SummarySkeleton extends StatelessWidget {
  const SummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
        child: Column(
          children: [
           Padding(
             padding: const EdgeInsets.symmetric(vertical: 10.0),
             child: _container(context, 50, MediaQuery.of(context).size.width*0.35),
           ),
            _container(context, 40, MediaQuery.of(context).size.width*0.55),
          ],
        ),
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!
    );
  }
}

Widget _container(BuildContext context, double height, double width){
  return Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      color: Colors.white,
        borderRadius: BorderRadius.circular(40)
    ),
  );
}


class SummaryListSkeleton extends StatelessWidget {
  const SummaryListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
        child: SizedBox(
          height: MediaQuery.of(context).size.height*0.27,
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount:10,
              itemBuilder: (context, index){
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    width: MediaQuery.of(context).size.width*0.4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                );
              }
          ),
        ),
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!
    );
  }
}
