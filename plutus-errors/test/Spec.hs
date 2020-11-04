import           Test.Tasty
import qualified Test.Tasty.HUnit                                 as HUnit
import Data.List

import Codes

main :: IO ()
main = defaultMain testNoDups

testNoDups :: TestTree
testNoDups =
    HUnit.testCase "noDuplicates" .
           HUnit.assertEqual "ErrorCode instances have some duplicate error-codes (numbers): " [] $ findDuplicates allCodes


-- | find the duplicate occurences in a list
findDuplicates :: Ord a => [a] -> [[a]]
findDuplicates xs = filter (\g -> length g >1) . group $ sort xs
